# frozen_string_literal: true

RSpec.describe SolidQueueAutoscaler::Dashboard do
  let(:config) do
    configure_autoscaler(
      min_workers: 1,
      max_workers: 10,
      scale_up_queue_depth: 100,
      scale_up_latency_seconds: 300,
      scale_down_queue_depth: 10,
      scale_down_latency_seconds: 30,
      queues: %w[default mailers]
    )
    SolidQueueAutoscaler.config
  end

  let(:metrics_result) do
    SolidQueueAutoscaler::Metrics::Result.new(
      queue_depth: 50,
      oldest_job_age_seconds: 60.0,
      jobs_per_minute: 100,
      claimed_jobs: 5,
      failed_jobs: 2,
      blocked_jobs: 0,
      active_workers: 3,
      queues_breakdown: { 'default' => 30, 'mailers' => 20 },
      collected_at: Time.current
    )
  end

  let(:adapter) do
    instance_double(
      SolidQueueAutoscaler::Adapters::Heroku,
      current_workers: 3,
      name: 'Heroku',
      configuration_errors: []
    )
  end

  let(:connection) { double('connection') }

  before do
    allow(config).to receive(:adapter).and_return(adapter)
    allow(config).to receive(:connection).and_return(connection)
    allow(connection).to receive(:table_exists?).and_return(false)
  end

  describe '.status' do
    it 'returns status for all registered workers' do
      configure_autoscaler
      allow(SolidQueueAutoscaler).to receive(:registered_workers).and_return([:default])
      allow(described_class).to receive(:worker_status).and_return({ name: :default })

      status = described_class.status

      expect(status).to have_key(:default)
    end

    it 'returns status for default worker when no workers registered' do
      allow(SolidQueueAutoscaler).to receive(:registered_workers).and_return([])
      allow(described_class).to receive(:worker_status).and_return({ name: :default })

      status = described_class.status

      expect(status).to have_key(:default)
    end

    it 'returns status for multiple workers' do
      SolidQueueAutoscaler.configure(:worker_a) do |c|
        c.heroku_api_key = 'test'
        c.heroku_app_name = 'test'
      end
      SolidQueueAutoscaler.configure(:worker_b) do |c|
        c.heroku_api_key = 'test'
        c.heroku_app_name = 'test'
      end

      allow(described_class).to receive(:worker_status).and_return({ name: :test })

      status = described_class.status

      expect(status.keys).to include(:worker_a, :worker_b)
    end
  end

  describe '.worker_status' do
    let(:tracker) { instance_double(SolidQueueAutoscaler::CooldownTracker) }

    before do
      allow(SolidQueueAutoscaler::CooldownTracker).to receive(:new).and_return(tracker)
      allow(tracker).to receive(:scale_up_cooldown_remaining).and_return(30.5)
      allow(tracker).to receive(:scale_down_cooldown_remaining).and_return(0.0)
      allow(tracker).to receive(:last_scale_up_at).and_return(Time.current - 90.seconds)
      allow(tracker).to receive(:last_scale_down_at).and_return(nil)
      allow(SolidQueueAutoscaler).to receive(:metrics).and_return(metrics_result)
      allow(SolidQueueAutoscaler).to receive(:current_workers).and_return(3)
    end

    it 'returns worker name' do
      status = described_class.worker_status(:default)
      expect(status[:name]).to eq(:default)
    end

    it 'returns enabled status' do
      status = described_class.worker_status(:default)
      expect(status[:enabled]).to be(true)
    end

    it 'returns dry_run status' do
      status = described_class.worker_status(:default)
      expect(status[:dry_run]).to be(true) # Default in test helper
    end

    it 'returns current worker count' do
      status = described_class.worker_status(:default)
      expect(status[:current_workers]).to eq(3)
    end

    it 'returns worker limits' do
      status = described_class.worker_status(:default)
      expect(status[:min_workers]).to eq(1)
      expect(status[:max_workers]).to eq(10)
    end

    it 'returns queues configuration' do
      status = described_class.worker_status(:default)
      expect(status[:queues]).to eq(%w[default mailers])
    end

    it 'returns process type' do
      status = described_class.worker_status(:default)
      expect(status[:process_type]).to eq('worker')
    end

    it 'returns scaling strategy' do
      status = described_class.worker_status(:default)
      expect(status[:scaling_strategy]).to eq(:fixed)
    end

    it 'returns metrics information' do
      status = described_class.worker_status(:default)

      expect(status[:metrics][:queue_depth]).to eq(50)
      expect(status[:metrics][:latency_seconds]).to eq(60.0)
      expect(status[:metrics][:jobs_per_minute]).to eq(100)
      expect(status[:metrics][:claimed_jobs]).to eq(5)
      expect(status[:metrics][:failed_jobs]).to eq(2)
      expect(status[:metrics][:active_workers]).to eq(3)
    end

    it 'returns cooldown information' do
      status = described_class.worker_status(:default)

      expect(status[:cooldowns][:scale_up_remaining]).to eq(31) # Rounded
      expect(status[:cooldowns][:scale_down_remaining]).to eq(0)
      expect(status[:cooldowns][:last_scale_up]).to be_within(1.second).of(Time.current - 90.seconds)
      expect(status[:cooldowns][:last_scale_down]).to be_nil
    end

    it 'returns threshold configuration' do
      status = described_class.worker_status(:default)

      expect(status[:thresholds][:scale_up_queue_depth]).to eq(100)
      expect(status[:thresholds][:scale_up_latency]).to eq(300)
      expect(status[:thresholds][:scale_down_queue_depth]).to eq(10)
      expect(status[:thresholds][:scale_down_latency]).to eq(30)
    end

    it 'handles metrics collection errors gracefully' do
      allow(SolidQueueAutoscaler).to receive(:metrics).and_raise(StandardError.new('DB error'))

      status = described_class.worker_status(:default)

      expect(status[:metrics][:queue_depth]).to eq(0)
      expect(status[:metrics][:latency_seconds]).to eq(0)
    end

    it 'handles current_workers errors gracefully' do
      allow(SolidQueueAutoscaler).to receive(:current_workers).and_raise(StandardError.new('API error'))

      status = described_class.worker_status(:default)

      expect(status[:current_workers]).to eq(0)
    end

    it 'returns default queues when none configured' do
      SolidQueueAutoscaler.configure(:no_queues) do |c|
        c.heroku_api_key = 'test'
        c.heroku_app_name = 'test'
        c.queues = nil
      end

      status = described_class.worker_status(:no_queues)

      expect(status[:queues]).to eq(['all'])
    end
  end

  describe '.recent_events' do
    it 'delegates to ScaleEvent.recent' do
      events = [
        SolidQueueAutoscaler::ScaleEvent.new(action: 'scale_up'),
        SolidQueueAutoscaler::ScaleEvent.new(action: 'scale_down')
      ]
      allow(SolidQueueAutoscaler::ScaleEvent).to receive(:recent).and_return(events)

      result = described_class.recent_events(limit: 20)

      expect(SolidQueueAutoscaler::ScaleEvent).to have_received(:recent).with(limit: 20, worker_name: nil)
      expect(result).to eq(events)
    end

    it 'passes worker_name filter' do
      allow(SolidQueueAutoscaler::ScaleEvent).to receive(:recent).and_return([])

      described_class.recent_events(limit: 10, worker_name: 'critical')

      expect(SolidQueueAutoscaler::ScaleEvent).to have_received(:recent)
        .with(limit: 10, worker_name: 'critical')
    end

    it 'uses default limit of 50' do
      allow(SolidQueueAutoscaler::ScaleEvent).to receive(:recent).and_return([])

      described_class.recent_events

      expect(SolidQueueAutoscaler::ScaleEvent).to have_received(:recent)
        .with(limit: 50, worker_name: nil)
    end
  end

  describe '.event_stats' do
    it 'delegates to ScaleEvent.stats' do
      stats = { total: 10, scale_up_count: 5 }
      allow(SolidQueueAutoscaler::ScaleEvent).to receive(:stats).and_return(stats)

      result = described_class.event_stats

      expect(result).to eq(stats)
    end

    it 'passes since parameter' do
      since_time = 1.hour.ago
      allow(SolidQueueAutoscaler::ScaleEvent).to receive(:stats).and_return({})

      described_class.event_stats(since: since_time)

      expect(SolidQueueAutoscaler::ScaleEvent).to have_received(:stats)
        .with(since: since_time, worker_name: nil)
    end

    it 'passes worker_name filter' do
      allow(SolidQueueAutoscaler::ScaleEvent).to receive(:stats).and_return({})

      described_class.event_stats(worker_name: 'batch')

      expect(SolidQueueAutoscaler::ScaleEvent).to have_received(:stats)
        .with(hash_including(worker_name: 'batch'))
    end

    it 'uses default since of 24 hours ago' do
      allow(SolidQueueAutoscaler::ScaleEvent).to receive(:stats).and_return({})

      described_class.event_stats

      expect(SolidQueueAutoscaler::ScaleEvent).to have_received(:stats) do |args|
        expect(args[:since]).to be_within(1.minute).of(24.hours.ago)
      end
    end
  end

  describe '.events_table_available?' do
    it 'returns true when table exists' do
      allow(SolidQueueAutoscaler::ScaleEvent).to receive(:table_exists?).and_return(true)

      expect(described_class.events_table_available?).to be(true)
    end

    it 'returns false when table does not exist' do
      allow(SolidQueueAutoscaler::ScaleEvent).to receive(:table_exists?).and_return(false)

      expect(described_class.events_table_available?).to be(false)
    end
  end

  describe 'integration with multi-worker configuration' do
    before do
      SolidQueueAutoscaler.reset_configuration!

      SolidQueueAutoscaler.configure(:critical_worker) do |c|
        c.heroku_api_key = 'test'
        c.heroku_app_name = 'test'
        c.process_type = 'critical'
        c.queues = ['critical']
        c.min_workers = 2
        c.max_workers = 20
      end

      SolidQueueAutoscaler.configure(:default_worker) do |c|
        c.heroku_api_key = 'test'
        c.heroku_app_name = 'test'
        c.process_type = 'worker'
        c.queues = ['default']
        c.min_workers = 1
        c.max_workers = 10
      end
    end

    it 'returns status for all configured workers' do
      # Stub out metrics and workers to avoid real API/DB calls
      allow(SolidQueueAutoscaler).to receive(:metrics).and_return(nil)
      allow(SolidQueueAutoscaler).to receive(:current_workers).and_return(0)

      status = described_class.status

      expect(status.keys).to contain_exactly(:critical_worker, :default_worker)
    end

    it 'returns correct configuration for each worker' do
      allow(SolidQueueAutoscaler).to receive(:metrics).and_return(nil)
      allow(SolidQueueAutoscaler).to receive(:current_workers).and_return(0)

      status = described_class.status

      expect(status[:critical_worker][:process_type]).to eq('critical')
      expect(status[:critical_worker][:queues]).to eq(['critical'])
      expect(status[:critical_worker][:min_workers]).to eq(2)
      expect(status[:critical_worker][:max_workers]).to eq(20)

      expect(status[:default_worker][:process_type]).to eq('worker')
      expect(status[:default_worker][:queues]).to eq(['default'])
      expect(status[:default_worker][:min_workers]).to eq(1)
      expect(status[:default_worker][:max_workers]).to eq(10)
    end
  end
end
