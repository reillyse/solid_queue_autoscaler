# frozen_string_literal: true

RSpec.describe SolidQueueAutoscaler::Scaler, 'persistent cooldowns' do
  let(:config) do
    c = SolidQueueAutoscaler::Configuration.new
    c.heroku_api_key = 'test-api-key'
    c.heroku_app_name = 'test-app'
    c.process_type = 'worker'
    c.min_workers = 1
    c.max_workers = 10
    c.scale_up_queue_depth = 100
    c.scale_up_latency_seconds = 300
    c.scale_down_queue_depth = 10
    c.scale_down_latency_seconds = 30
    c.cooldown_seconds = 120
    c.scale_up_increment = 1
    c.scale_down_decrement = 1
    c.dry_run = false
    c.enabled = true
    c.persist_cooldowns = true
    c
  end

  let(:lock) { instance_double(SolidQueueAutoscaler::AdvisoryLock) }
  let(:metrics_collector) { instance_double(SolidQueueAutoscaler::Metrics) }
  let(:adapter) { instance_double(SolidQueueAutoscaler::Adapters::Heroku) }
  let(:cooldown_tracker) { instance_double(SolidQueueAutoscaler::CooldownTracker) }

  let(:high_queue_metrics) do
    SolidQueueAutoscaler::Metrics::Result.new(
      queue_depth: 200,
      oldest_job_age_seconds: 60,
      jobs_per_minute: 10,
      claimed_jobs: 5,
      failed_jobs: 0,
      blocked_jobs: 0,
      active_workers: 2,
      queues_breakdown: {},
      collected_at: Time.current
    )
  end

  let(:low_queue_metrics) do
    SolidQueueAutoscaler::Metrics::Result.new(
      queue_depth: 5,
      oldest_job_age_seconds: 10,
      jobs_per_minute: 1,
      claimed_jobs: 0,
      failed_jobs: 0,
      blocked_jobs: 0,
      active_workers: 5,
      queues_breakdown: {},
      collected_at: Time.current
    )
  end

  subject(:scaler) { described_class.new(config: config) }

  before do
    allow(SolidQueueAutoscaler::AdvisoryLock).to receive(:new).and_return(lock)
    allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)
    allow(config).to receive(:adapter).and_return(adapter)
    allow(SolidQueueAutoscaler::CooldownTracker).to receive(:new).and_return(cooldown_tracker)
    allow(lock).to receive(:try_lock).and_return(true)
    allow(lock).to receive(:release)

    # Stub ScaleEvent to avoid database calls
    allow(SolidQueueAutoscaler::ScaleEvent).to receive(:create!)
    allow(config).to receive(:record_events?).and_return(false)
  end

  describe 'when persist_cooldowns is enabled and table exists' do
    before do
      allow(cooldown_tracker).to receive(:table_exists?).and_return(true)
    end

    context 'cooldown_active?' do
      it 'delegates scale_up cooldown check to CooldownTracker' do
        allow(metrics_collector).to receive(:collect).and_return(high_queue_metrics)
        allow(adapter).to receive(:current_workers).and_return(2)
        allow(cooldown_tracker).to receive(:cooldown_active_for_scale_up?).and_return(true)
        allow(cooldown_tracker).to receive(:scale_up_cooldown_remaining).and_return(60)

        result = scaler.run
        expect(result.skipped_reason).to include('Cooldown active')
        expect(cooldown_tracker).to have_received(:cooldown_active_for_scale_up?)
      end

      it 'delegates scale_down cooldown check to CooldownTracker' do
        allow(metrics_collector).to receive(:collect).and_return(low_queue_metrics)
        allow(adapter).to receive(:current_workers).and_return(5)
        allow(cooldown_tracker).to receive(:cooldown_active_for_scale_down?).and_return(true)
        allow(cooldown_tracker).to receive(:scale_down_cooldown_remaining).and_return(60)

        result = scaler.run
        expect(result.skipped_reason).to include('Cooldown active')
        expect(cooldown_tracker).to have_received(:cooldown_active_for_scale_down?)
      end
    end

    context 'record_scale_time' do
      it 'records scale_up to CooldownTracker' do
        allow(metrics_collector).to receive(:collect).and_return(high_queue_metrics)
        allow(adapter).to receive(:current_workers).and_return(2)
        allow(adapter).to receive(:scale)
        allow(cooldown_tracker).to receive(:cooldown_active_for_scale_up?).and_return(false)
        allow(cooldown_tracker).to receive(:record_scale_up!)

        scaler.run
        expect(cooldown_tracker).to have_received(:record_scale_up!)
      end

      it 'records scale_down to CooldownTracker' do
        allow(metrics_collector).to receive(:collect).and_return(low_queue_metrics)
        allow(adapter).to receive(:current_workers).and_return(5)
        allow(adapter).to receive(:scale)
        allow(cooldown_tracker).to receive(:cooldown_active_for_scale_down?).and_return(false)
        allow(cooldown_tracker).to receive(:record_scale_down!)

        scaler.run
        expect(cooldown_tracker).to have_received(:record_scale_down!)
      end
    end
  end

  describe 'when persist_cooldowns is enabled but table does not exist' do
    before do
      allow(cooldown_tracker).to receive(:table_exists?).and_return(false)
      described_class.reset_cooldowns!
    end

    it 'falls back to in-memory cooldowns' do
      allow(metrics_collector).to receive(:collect).and_return(high_queue_metrics)
      allow(adapter).to receive(:current_workers).and_return(2)
      allow(adapter).to receive(:scale)

      # First scale should succeed
      result1 = scaler.run
      expect(result1.success?).to be true
      expect(result1.scaled?).to be true

      # Second scale should be blocked by in-memory cooldown
      result2 = scaler.run
      expect(result2.skipped_reason).to include('Cooldown active')
    end
  end

  describe 'when persist_cooldowns is disabled' do
    before do
      config.persist_cooldowns = false
      described_class.reset_cooldowns!
    end

    it 'uses in-memory cooldowns and does not instantiate CooldownTracker' do
      allow(metrics_collector).to receive(:collect).and_return(high_queue_metrics)
      allow(adapter).to receive(:current_workers).and_return(2)
      allow(adapter).to receive(:scale)

      # First scale should succeed
      result1 = scaler.run
      expect(result1.success?).to be true
      expect(result1.scaled?).to be true

      # Second scale should be blocked by in-memory cooldown
      result2 = scaler.run
      expect(result2.skipped_reason).to include('Cooldown active')

      expect(SolidQueueAutoscaler::CooldownTracker).not_to have_received(:new)
    end
  end

  describe 'Configuration#persist_cooldowns' do
    it 'defaults to true' do
      fresh_config = SolidQueueAutoscaler::Configuration.new
      expect(fresh_config.persist_cooldowns).to be true
    end

    it 'can be set to false' do
      fresh_config = SolidQueueAutoscaler::Configuration.new
      fresh_config.persist_cooldowns = false
      expect(fresh_config.persist_cooldowns).to be false
    end
  end
end
