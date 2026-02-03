# frozen_string_literal: true

# Integration tests for the scale-to-zero workflow.
#
# This tests the complete lifecycle of scaling workers to zero and back up:
# 1. Formation exists with workers running
# 2. Queue becomes idle, workers scale down to 0
# 3. Heroku removes the formation (returns 404 on API calls)
# 4. Autoscaler correctly handles 404 as "0 workers"
# 5. New jobs arrive, queue depth increases
# 6. Autoscaler scales up, creating formation via batch_update
#
# This workflow was broken before v1.0.15 where 404 errors would raise exceptions
# instead of being handled gracefully.

RSpec.describe 'Scale-to-Zero Workflow', type: :integration do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil) }

  # Helper to create Excon errors with response details
  def excon_error_with_status(message, status:, body: '{}')
    response = double('response', status: status, body: body)
    error = Excon::Error.new(message)
    error.define_singleton_method(:response) { response }
    error
  end

  describe 'Heroku Adapter 404 Handling' do
    let(:formation_client) { instance_double('PlatformAPI::Formation') }
    let(:platform_client) { instance_double('PlatformAPI::Client', formation: formation_client) }

    let(:config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.heroku_api_key = 'test-api-key'
        c.heroku_app_name = 'test-app'
        c.process_type = 'worker'
        c.min_workers = 0  # Enable scale-to-zero
        c.max_workers = 10
        c.dry_run = false
        c.logger = logger
      end
    end

    subject(:adapter) { SolidQueueAutoscaler::Adapters::Heroku.new(config: config) }

    before do
      allow(PlatformAPI).to receive(:connect_oauth).with('test-api-key').and_return(platform_client)
    end

    describe 'when formation exists' do
      before do
        allow(formation_client).to receive(:info)
          .with('test-app', 'worker')
          .and_return({ 'quantity' => 3, 'type' => 'worker' })
      end

      it 'returns the current worker count' do
        expect(adapter.current_workers).to eq(3)
      end
    end

    describe 'when formation is scaled to zero and removed by Heroku (404)' do
      before do
        allow(formation_client).to receive(:info)
          .with('test-app', 'worker')
          .and_raise(excon_error_with_status(
            'Not Found',
            status: 404,
            body: '{"id":"not_found","message":"Couldn\'t find that formation."}'
          ))
      end

      it 'returns 0 workers instead of raising an error' do
        expect(adapter.current_workers).to eq(0)
      end

      it 'logs a debug message about the missing formation' do
        adapter.current_workers
        expect(logger).to have_received(:debug).with(/Formation 'worker' not found, treating as 0 workers/)
      end
    end

    describe 'scaling up when formation does not exist (404 on update)' do
      before do
        # formation.update returns 404 because formation doesn't exist
        allow(formation_client).to receive(:update)
          .with('test-app', 'worker', { quantity: 3 })
          .and_raise(excon_error_with_status(
            'Not Found',
            status: 404,
            body: '{"id":"not_found","message":"Couldn\'t find that formation."}'
          ))

        # batch_update successfully creates the formation
        allow(formation_client).to receive(:batch_update)
          .with('test-app', { updates: [{ type: 'worker', quantity: 3 }] })
          .and_return([{ 'type' => 'worker', 'quantity' => 3 }])
      end

      it 'falls back to batch_update to create the formation' do
        result = adapter.scale(3)
        expect(result).to eq(3)
        expect(formation_client).to have_received(:batch_update)
      end

      it 'logs info about creating the formation' do
        adapter.scale(3)
        expect(logger).to have_received(:info).with(/Formation 'worker' not found, creating with quantity 3/)
      end
    end

    describe 'complete scale-to-zero -> scale-up cycle' do
      it 'handles the full workflow correctly' do
        # Phase 1: Formation exists with 3 workers
        allow(formation_client).to receive(:info)
          .with('test-app', 'worker')
          .and_return({ 'quantity' => 3 })
        expect(adapter.current_workers).to eq(3)

        # Phase 2: Scale down to 0
        allow(formation_client).to receive(:update)
          .with('test-app', 'worker', { quantity: 0 })
          .and_return({ 'quantity' => 0 })
        expect(adapter.scale(0)).to eq(0)

        # Phase 3: Formation is now removed by Heroku (404 on info)
        error_404 = excon_error_with_status('Not Found', status: 404)
        allow(formation_client).to receive(:info).and_raise(error_404)
        expect(adapter.current_workers).to eq(0)

        # Phase 4: Scale back up - update fails with 404, batch_update creates it
        allow(formation_client).to receive(:update)
          .with('test-app', 'worker', { quantity: 2 })
          .and_raise(error_404)
        allow(formation_client).to receive(:batch_update)
          .with('test-app', { updates: [{ type: 'worker', quantity: 2 }] })
          .and_return([{ 'type' => 'worker', 'quantity' => 2 }])

        expect(adapter.scale(2)).to eq(2)
        expect(formation_client).to have_received(:batch_update)
      end
    end
  end

  describe 'Scaler with min_workers=0 Configuration' do
    let(:formation_client) { instance_double('PlatformAPI::Formation') }
    let(:platform_client) { instance_double('PlatformAPI::Client', formation: formation_client) }
    let(:lock) { instance_double(SolidQueueAutoscaler::AdvisoryLock) }

    let(:config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.heroku_api_key = 'test-api-key'
        c.heroku_app_name = 'test-app'
        c.process_type = 'worker'
        c.min_workers = 0  # Enable scale-to-zero
        c.max_workers = 10
        c.scale_up_queue_depth = 1  # Scale up when any job is queued
        c.scale_up_latency_seconds = 60
        c.scale_up_increment = 1
        c.scale_down_queue_depth = 0  # Scale down when completely idle
        c.scale_down_latency_seconds = 10
        c.scale_down_decrement = 1
        c.cooldown_seconds = 60
        c.scale_up_cooldown_seconds = 30  # Quick scale up for responsiveness
        c.scale_down_cooldown_seconds = 300  # Slow scale down to avoid premature zero
        c.dry_run = false
        c.enabled = true
        c.persist_cooldowns = false
        c.record_events = false
        c.logger = logger
      end
    end

    let(:adapter) { SolidQueueAutoscaler::Adapters::Heroku.new(config: config) }

    before do
      allow(PlatformAPI).to receive(:connect_oauth).and_return(platform_client)
      config.adapter = adapter

      allow(SolidQueueAutoscaler::AdvisoryLock).to receive(:new).and_return(lock)
      allow(lock).to receive(:try_lock).and_return(true)
      allow(lock).to receive(:release)

      SolidQueueAutoscaler::Scaler.reset_cooldowns!
    end

    describe 'scaling down to zero workers' do
      let(:idle_metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 0,
          oldest_job_age_seconds: 0.0,
          jobs_per_minute: 0,
          claimed_jobs: 0,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 1,
          queues_breakdown: {},
          collected_at: Time.current
        )
      end

      let(:metrics_collector) { instance_double(SolidQueueAutoscaler::Metrics, collect: idle_metrics) }

      before do
        allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)
        allow(formation_client).to receive(:info)
          .with('test-app', 'worker')
          .and_return({ 'quantity' => 1 })
        allow(formation_client).to receive(:update)
          .with('test-app', 'worker', { quantity: 0 })
          .and_return({ 'quantity' => 0 })
      end

      it 'scales down to zero when queue is idle' do
        scaler = SolidQueueAutoscaler::Scaler.new(config: config)
        result = scaler.run

        expect(result.success?).to be(true)
        expect(result.scaled?).to be(true)
        expect(result.decision.action).to eq(:scale_down)
        expect(result.decision.to).to eq(0)
        expect(formation_client).to have_received(:update).with('test-app', 'worker', { quantity: 0 })
      end
    end

    describe 'scaling up from zero when formation removed (404)' do
      let(:high_queue_metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 50,  # Jobs waiting in queue
          oldest_job_age_seconds: 120.0,
          jobs_per_minute: 0,
          claimed_jobs: 0,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 0,
          queues_breakdown: { 'default' => 50 },
          collected_at: Time.current
        )
      end

      let(:metrics_collector) { instance_double(SolidQueueAutoscaler::Metrics, collect: high_queue_metrics) }
      let(:error_404) { excon_error_with_status('Not Found', status: 404) }

      before do
        allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)

        # Formation doesn't exist (404 on info)
        allow(formation_client).to receive(:info)
          .with('test-app', 'worker')
          .and_raise(error_404)

        # formation.update also fails with 404
        allow(formation_client).to receive(:update)
          .with('test-app', 'worker', { quantity: 1 })
          .and_raise(error_404)

        # batch_update succeeds and creates the formation
        allow(formation_client).to receive(:batch_update)
          .with('test-app', { updates: [{ type: 'worker', quantity: 1 }] })
          .and_return([{ 'type' => 'worker', 'quantity' => 1 }])
      end

      it 'detects zero workers from 404 response' do
        scaler = SolidQueueAutoscaler::Scaler.new(config: config)
        result = scaler.run

        expect(result.success?).to be(true)
        expect(result.decision.from).to eq(0)
      end

      it 'scales up and creates formation via batch_update' do
        scaler = SolidQueueAutoscaler::Scaler.new(config: config)
        result = scaler.run

        expect(result.success?).to be(true)
        expect(result.scaled?).to be(true)
        expect(result.decision.action).to eq(:scale_up)
        expect(formation_client).to have_received(:batch_update)
      end
    end

    describe 'complete workflow through Scaler' do
      let(:metrics_collector) { instance_double(SolidQueueAutoscaler::Metrics) }

      before do
        allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)
      end

      it 'handles full scale-to-zero lifecycle' do
        scaler = SolidQueueAutoscaler::Scaler.new(config: config)

        # Step 1: Running with workers, queue becomes idle -> scale down to 1
        allow(formation_client).to receive(:info).and_return({ 'quantity' => 3 })
        allow(formation_client).to receive(:update).and_return({ 'quantity' => 2 })
        allow(metrics_collector).to receive(:collect).and_return(
          SolidQueueAutoscaler::Metrics::Result.new(
            queue_depth: 0, oldest_job_age_seconds: 0.0, jobs_per_minute: 0,
            claimed_jobs: 0, failed_jobs: 0, blocked_jobs: 0, active_workers: 3,
            queues_breakdown: {}, collected_at: Time.current
          )
        )

        result1 = scaler.run
        expect(result1.decision.action).to eq(:scale_down)
        expect(result1.decision.from).to eq(3)

        # Step 2: Reset cooldown and continue to scale down to 0
        SolidQueueAutoscaler::Scaler.reset_cooldowns!
        allow(formation_client).to receive(:info).and_return({ 'quantity' => 1 })
        allow(formation_client).to receive(:update)
          .with('test-app', 'worker', { quantity: 0 })
          .and_return({ 'quantity' => 0 })

        result2 = scaler.run
        expect(result2.decision.action).to eq(:scale_down)
        expect(result2.decision.to).to eq(0)

        # Step 3: Formation removed by Heroku, jobs arrive
        SolidQueueAutoscaler::Scaler.reset_cooldowns!
        error_404 = excon_error_with_status('Not Found', status: 404)
        allow(formation_client).to receive(:info).and_raise(error_404)
        allow(formation_client).to receive(:update)
          .with('test-app', 'worker', { quantity: 1 })
          .and_raise(error_404)
        allow(formation_client).to receive(:batch_update)
          .and_return([{ 'type' => 'worker', 'quantity' => 1 }])
        allow(metrics_collector).to receive(:collect).and_return(
          SolidQueueAutoscaler::Metrics::Result.new(
            queue_depth: 25, oldest_job_age_seconds: 90.0, jobs_per_minute: 0,
            claimed_jobs: 0, failed_jobs: 0, blocked_jobs: 0, active_workers: 0,
            queues_breakdown: { 'default' => 25 }, collected_at: Time.current
          )
        )

        result3 = scaler.run
        expect(result3.success?).to be(true)
        expect(result3.scaled?).to be(true)
        expect(result3.decision.action).to eq(:scale_up)
        expect(result3.decision.from).to eq(0)
        expect(result3.decision.to).to eq(1)
        expect(formation_client).to have_received(:batch_update)
      end
    end
  end

  describe 'Decision Engine with min_workers=0' do
    let(:config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.heroku_api_key = 'test-key'
        c.heroku_app_name = 'test-app'
        c.min_workers = 0
        c.max_workers = 10
        c.scale_up_queue_depth = 1
        c.scale_up_latency_seconds = 60
        c.scale_up_increment = 1
        c.scale_down_queue_depth = 0
        c.scale_down_latency_seconds = 10
        c.scale_down_decrement = 1
      end
    end

    subject(:engine) { SolidQueueAutoscaler::DecisionEngine.new(config: config) }

    describe 'when at zero workers with jobs in queue' do
      let(:metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 10,
          oldest_job_age_seconds: 30.0,
          jobs_per_minute: 0,
          claimed_jobs: 0,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 0,
          queues_breakdown: { 'default' => 10 },
          collected_at: Time.current
        )
      end

      it 'decides to scale up from 0 to 1' do
        decision = engine.decide(metrics: metrics, current_workers: 0)

        expect(decision.action).to eq(:scale_up)
        expect(decision.from).to eq(0)
        expect(decision.to).to eq(1)
      end
    end

    describe 'when at zero workers with empty queue' do
      let(:metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 0,
          oldest_job_age_seconds: 0.0,
          jobs_per_minute: 0,
          claimed_jobs: 0,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 0,
          queues_breakdown: {},
          collected_at: Time.current
        )
      end

      it 'decides no change (stays at 0)' do
        decision = engine.decide(metrics: metrics, current_workers: 0)

        expect(decision.action).to eq(:no_change)
        expect(decision.from).to eq(0)
        expect(decision.to).to eq(0)
        expect(decision.reason).to include('min_workers')
      end
    end

    describe 'when at 1 worker with completely idle queue' do
      let(:metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 0,
          oldest_job_age_seconds: 0.0,
          jobs_per_minute: 0,
          claimed_jobs: 0,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 1,
          queues_breakdown: {},
          collected_at: Time.current
        )
      end

      it 'decides to scale down to 0' do
        decision = engine.decide(metrics: metrics, current_workers: 1)

        expect(decision.action).to eq(:scale_down)
        expect(decision.from).to eq(1)
        expect(decision.to).to eq(0)
      end
    end
  end

  describe 'Multiple Worker Types with Different min_workers' do
    let(:formation_client) { instance_double('PlatformAPI::Formation') }
    let(:platform_client) { instance_double('PlatformAPI::Client', formation: formation_client) }
    let(:lock) { instance_double(SolidQueueAutoscaler::AdvisoryLock) }

    # Batch worker can scale to zero (for cost savings)
    let(:batch_config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.name = :batch_worker
        c.heroku_api_key = 'test-key'
        c.heroku_app_name = 'test-app'
        c.process_type = 'batch_worker'
        c.min_workers = 0
        c.max_workers = 5
        c.scale_up_queue_depth = 1
        c.scale_down_queue_depth = 0
        c.scale_down_latency_seconds = 10
        c.dry_run = false
        c.enabled = true
        c.persist_cooldowns = false
        c.logger = logger
      end
    end

    # Realtime worker must always have at least 1
    let(:realtime_config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.name = :realtime_worker
        c.heroku_api_key = 'test-key'
        c.heroku_app_name = 'test-app'
        c.process_type = 'realtime_worker'
        c.min_workers = 1  # Cannot scale to zero
        c.max_workers = 10
        c.scale_up_queue_depth = 50
        c.scale_down_queue_depth = 5
        c.dry_run = false
        c.enabled = true
        c.persist_cooldowns = false
        c.logger = logger
      end
    end

    before do
      allow(PlatformAPI).to receive(:connect_oauth).and_return(platform_client)
      allow(SolidQueueAutoscaler::AdvisoryLock).to receive(:new).and_return(lock)
      allow(lock).to receive(:try_lock).and_return(true)
      allow(lock).to receive(:release)
    end

    it 'allows batch_worker to scale to zero' do
      batch_config.adapter = SolidQueueAutoscaler::Adapters::Heroku.new(config: batch_config)

      idle_metrics = SolidQueueAutoscaler::Metrics::Result.new(
        queue_depth: 0, oldest_job_age_seconds: 0.0, jobs_per_minute: 0,
        claimed_jobs: 0, failed_jobs: 0, blocked_jobs: 0, active_workers: 1,
        queues_breakdown: {}, collected_at: Time.current
      )
      metrics_collector = instance_double(SolidQueueAutoscaler::Metrics, collect: idle_metrics)
      allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)

      allow(formation_client).to receive(:info)
        .with('test-app', 'batch_worker')
        .and_return({ 'quantity' => 1 })
      allow(formation_client).to receive(:update)
        .with('test-app', 'batch_worker', { quantity: 0 })
        .and_return({ 'quantity' => 0 })

      SolidQueueAutoscaler::Scaler.reset_cooldowns!
      scaler = SolidQueueAutoscaler::Scaler.new(config: batch_config)
      result = scaler.run

      expect(result.decision.action).to eq(:scale_down)
      expect(result.decision.to).to eq(0)
    end

    it 'prevents realtime_worker from scaling below 1' do
      realtime_config.adapter = SolidQueueAutoscaler::Adapters::Heroku.new(config: realtime_config)

      idle_metrics = SolidQueueAutoscaler::Metrics::Result.new(
        queue_depth: 0, oldest_job_age_seconds: 0.0, jobs_per_minute: 0,
        claimed_jobs: 0, failed_jobs: 0, blocked_jobs: 0, active_workers: 1,
        queues_breakdown: {}, collected_at: Time.current
      )
      metrics_collector = instance_double(SolidQueueAutoscaler::Metrics, collect: idle_metrics)
      allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)

      allow(formation_client).to receive(:info)
        .with('test-app', 'realtime_worker')
        .and_return({ 'quantity' => 1 })

      SolidQueueAutoscaler::Scaler.reset_cooldowns!
      scaler = SolidQueueAutoscaler::Scaler.new(config: realtime_config)
      result = scaler.run

      expect(result.decision.action).to eq(:no_change)
      expect(result.decision.reason).to include('min_workers')
    end
  end

  describe 'Error Handling: 404 vs Other HTTP Errors' do
    let(:formation_client) { instance_double('PlatformAPI::Formation') }
    let(:platform_client) { instance_double('PlatformAPI::Client', formation: formation_client) }

    let(:config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.heroku_api_key = 'test-key'
        c.heroku_app_name = 'test-app'
        c.process_type = 'worker'
        c.min_workers = 0
        c.dry_run = false
        c.logger = logger
      end
    end

    subject(:adapter) { SolidQueueAutoscaler::Adapters::Heroku.new(config: config) }

    before do
      allow(PlatformAPI).to receive(:connect_oauth).and_return(platform_client)
    end

    describe '404 is handled gracefully' do
      before do
        allow(formation_client).to receive(:info)
          .and_raise(excon_error_with_status('Not Found', status: 404))
      end

      it 'returns 0 for current_workers' do
        expect(adapter.current_workers).to eq(0)
      end

      it 'does not raise an error' do
        expect { adapter.current_workers }.not_to raise_error
      end
    end

    describe '401 Unauthorized still raises an error' do
      before do
        allow(formation_client).to receive(:info)
          .and_raise(excon_error_with_status('Unauthorized', status: 401))
      end

      it 'raises HerokuAPIError' do
        expect { adapter.current_workers }.to raise_error(SolidQueueAutoscaler::HerokuAPIError)
      end
    end

    describe '403 Forbidden still raises an error' do
      before do
        allow(formation_client).to receive(:info)
          .and_raise(excon_error_with_status('Forbidden', status: 403))
      end

      it 'raises HerokuAPIError' do
        expect { adapter.current_workers }.to raise_error(SolidQueueAutoscaler::HerokuAPIError)
      end
    end

    describe '500 Internal Server Error still raises an error' do
      before do
        allow(formation_client).to receive(:info)
          .and_raise(excon_error_with_status('Internal Server Error', status: 500))
      end

      it 'raises HerokuAPIError' do
        expect { adapter.current_workers }.to raise_error(SolidQueueAutoscaler::HerokuAPIError)
      end
    end
  end

  describe 'Dry Run Mode with Scale-to-Zero' do
    let(:formation_client) { instance_double('PlatformAPI::Formation') }
    let(:platform_client) { instance_double('PlatformAPI::Client', formation: formation_client) }
    let(:lock) { instance_double(SolidQueueAutoscaler::AdvisoryLock) }

    let(:config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.heroku_api_key = 'test-key'
        c.heroku_app_name = 'test-app'
        c.process_type = 'worker'
        c.min_workers = 0
        c.max_workers = 5
        c.scale_down_queue_depth = 0
        c.scale_down_latency_seconds = 10
        c.dry_run = true  # Dry run enabled
        c.enabled = true
        c.persist_cooldowns = false
        c.logger = logger
      end
    end

    before do
      allow(PlatformAPI).to receive(:connect_oauth).and_return(platform_client)
      config.adapter = SolidQueueAutoscaler::Adapters::Heroku.new(config: config)

      allow(SolidQueueAutoscaler::AdvisoryLock).to receive(:new).and_return(lock)
      allow(lock).to receive(:try_lock).and_return(true)
      allow(lock).to receive(:release)

      # Formation exists with 1 worker
      allow(formation_client).to receive(:info)
        .with('test-app', 'worker')
        .and_return({ 'quantity' => 1 })

      SolidQueueAutoscaler::Scaler.reset_cooldowns!
    end

    it 'logs dry run scale-to-zero without making API calls' do
      idle_metrics = SolidQueueAutoscaler::Metrics::Result.new(
        queue_depth: 0, oldest_job_age_seconds: 0.0, jobs_per_minute: 0,
        claimed_jobs: 0, failed_jobs: 0, blocked_jobs: 0, active_workers: 1,
        queues_breakdown: {}, collected_at: Time.current
      )
      metrics_collector = instance_double(SolidQueueAutoscaler::Metrics, collect: idle_metrics)
      allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)

      # Allow update to be called (so we can verify it wasn't)
      allow(formation_client).to receive(:update)

      scaler = SolidQueueAutoscaler::Scaler.new(config: config)
      result = scaler.run

      expect(result.success?).to be(true)
      expect(result.scaled?).to be(true)
      expect(result.decision.action).to eq(:scale_down)
      expect(result.decision.to).to eq(0)

      # In dry run, formation.update should not be called
      expect(formation_client).not_to have_received(:update)
      expect(logger).to have_received(:info).with(/\[DRY RUN\].*scale.*worker.*0.*dynos/)
    end
  end

  describe 'Cold Start Scenario' do
    # Tests the scenario where the autoscaler starts up and the formation doesn't exist
    let(:formation_client) { instance_double('PlatformAPI::Formation') }
    let(:platform_client) { instance_double('PlatformAPI::Client', formation: formation_client) }
    let(:lock) { instance_double(SolidQueueAutoscaler::AdvisoryLock) }

    let(:config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.heroku_api_key = 'test-key'
        c.heroku_app_name = 'test-app'
        c.process_type = 'worker'
        c.min_workers = 0
        c.max_workers = 10
        c.scale_up_queue_depth = 1
        c.scale_up_increment = 2
        c.dry_run = false
        c.enabled = true
        c.persist_cooldowns = false
        c.logger = logger
      end
    end

    before do
      allow(PlatformAPI).to receive(:connect_oauth).and_return(platform_client)
      config.adapter = SolidQueueAutoscaler::Adapters::Heroku.new(config: config)

      allow(SolidQueueAutoscaler::AdvisoryLock).to receive(:new).and_return(lock)
      allow(lock).to receive(:try_lock).and_return(true)
      allow(lock).to receive(:release)

      SolidQueueAutoscaler::Scaler.reset_cooldowns!
    end

    it 'handles initial 404 and scales up correctly on first run' do
      error_404 = excon_error_with_status('Not Found', status: 404)

      # Formation doesn't exist
      allow(formation_client).to receive(:info).and_raise(error_404)
      allow(formation_client).to receive(:update).and_raise(error_404)
      allow(formation_client).to receive(:batch_update)
        .with('test-app', { updates: [{ type: 'worker', quantity: 2 }] })
        .and_return([{ 'type' => 'worker', 'quantity' => 2 }])

      # Jobs are waiting
      metrics = SolidQueueAutoscaler::Metrics::Result.new(
        queue_depth: 100, oldest_job_age_seconds: 300.0, jobs_per_minute: 0,
        claimed_jobs: 0, failed_jobs: 0, blocked_jobs: 0, active_workers: 0,
        queues_breakdown: { 'default' => 100 }, collected_at: Time.current
      )
      metrics_collector = instance_double(SolidQueueAutoscaler::Metrics, collect: metrics)
      allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)

      scaler = SolidQueueAutoscaler::Scaler.new(config: config)
      result = scaler.run

      expect(result.success?).to be(true)
      expect(result.scaled?).to be(true)
      expect(result.decision.action).to eq(:scale_up)
      expect(result.decision.from).to eq(0)
      expect(result.decision.to).to eq(2)  # scale_up_increment = 2
      expect(formation_client).to have_received(:batch_update)
    end
  end

  describe 'Scale-from-Zero with Lower Thresholds' do
    # Tests the new scale-from-zero feature that uses lower thresholds
    # when at 0 workers to enable faster cold start
    let(:config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.heroku_api_key = 'test-key'
        c.heroku_app_name = 'test-app'
        c.min_workers = 0
        c.max_workers = 10
        # Normal thresholds are high
        c.scale_up_queue_depth = 100
        c.scale_up_latency_seconds = 300
        # Scale-from-zero thresholds are low
        c.scale_from_zero_queue_depth = 1
        c.scale_from_zero_latency_seconds = 1.0
        c.scale_up_increment = 1
      end
    end

    subject(:engine) { SolidQueueAutoscaler::DecisionEngine.new(config: config) }

    describe 'when at zero workers with 1 job that is old enough' do
      let(:metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 1,  # Just 1 job - below normal threshold of 100
          oldest_job_age_seconds: 2.0,  # 2 seconds old - above scale_from_zero_latency_seconds
          jobs_per_minute: 0,
          claimed_jobs: 0,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 0,
          queues_breakdown: { 'default' => 1 },
          collected_at: Time.current
        )
      end

      it 'scales up using lower scale-from-zero thresholds' do
        decision = engine.decide(metrics: metrics, current_workers: 0)

        expect(decision.action).to eq(:scale_up)
        expect(decision.from).to eq(0)
        expect(decision.to).to eq(1)
        expect(decision.reason).to include('scale_from_zero')
      end
    end

    describe 'when at zero workers with 1 job that is too new' do
      let(:metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 1,  # 1 job in queue
          oldest_job_age_seconds: 0.5,  # Only 0.5 seconds old - below threshold
          jobs_per_minute: 0,
          claimed_jobs: 0,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 0,
          queues_breakdown: { 'default' => 1 },
          collected_at: Time.current
        )
      end

      it 'does NOT scale up (job too new, give other workers a chance)' do
        decision = engine.decide(metrics: metrics, current_workers: 0)

        expect(decision.action).to eq(:no_change)
        expect(decision.from).to eq(0)
        expect(decision.to).to eq(0)
      end
    end

    describe 'when at 1 worker with moderate queue depth' do
      let(:metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 50,  # Between scale_down (0) and scale_up (100) thresholds
          oldest_job_age_seconds: 60.0,  # Between scale_down (10s) and scale_up (300s)
          jobs_per_minute: 0,
          claimed_jobs: 10,  # Some jobs being worked on (not idle)
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 1,
          queues_breakdown: { 'default' => 50 },
          collected_at: Time.current
        )
      end

      it 'does NOT scale up (uses normal thresholds when not at 0)' do
        decision = engine.decide(metrics: metrics, current_workers: 1)

        # Should NOT scale up because we're not at 0 workers,
        # so normal thresholds apply (queue_depth 50 < 100)
        expect(decision.action).to eq(:no_change)
        expect(decision.from).to eq(1)
        expect(decision.to).to eq(1)
      end
    end

    describe 'cooldown bypass when scaling from zero' do
      let(:formation_client) { instance_double('PlatformAPI::Formation') }
      let(:platform_client) { instance_double('PlatformAPI::Client', formation: formation_client) }
      let(:lock) { instance_double(SolidQueueAutoscaler::AdvisoryLock) }

      let(:scaler_config) do
        SolidQueueAutoscaler::Configuration.new.tap do |c|
          c.heroku_api_key = 'test-key'
          c.heroku_app_name = 'test-app'
          c.process_type = 'worker'
          c.min_workers = 0
          c.max_workers = 10
          c.scale_up_queue_depth = 100
          c.scale_up_latency_seconds = 300
          c.scale_from_zero_queue_depth = 1
          c.scale_from_zero_latency_seconds = 1.0
          c.scale_up_increment = 1
          c.cooldown_seconds = 300  # 5 minute cooldown
          c.scale_up_cooldown_seconds = 300
          c.dry_run = false
          c.enabled = true
          c.persist_cooldowns = false
          c.record_events = false
          c.logger = logger
        end
      end

      before do
        allow(PlatformAPI).to receive(:connect_oauth).and_return(platform_client)
        scaler_config.adapter = SolidQueueAutoscaler::Adapters::Heroku.new(config: scaler_config)

        allow(SolidQueueAutoscaler::AdvisoryLock).to receive(:new).and_return(lock)
        allow(lock).to receive(:try_lock).and_return(true)
        allow(lock).to receive(:release)

        # Start with a recent scale-up recorded (should normally block scaling)
        SolidQueueAutoscaler::Scaler.reset_cooldowns!
        SolidQueueAutoscaler::Scaler.set_last_scale_up_at(scaler_config.name, Time.current - 10) # 10 seconds ago
      end

      it 'bypasses cooldown when scaling from 0 workers' do
        error_404 = excon_error_with_status('Not Found', status: 404)

        # At 0 workers
        allow(formation_client).to receive(:info).and_raise(error_404)
        allow(formation_client).to receive(:update).and_raise(error_404)
        allow(formation_client).to receive(:batch_update)
          .and_return([{ 'type' => 'worker', 'quantity' => 1 }])

        # 1 job, old enough
        metrics = SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 1, oldest_job_age_seconds: 2.0, jobs_per_minute: 0,
          claimed_jobs: 0, failed_jobs: 0, blocked_jobs: 0, active_workers: 0,
          queues_breakdown: { 'default' => 1 }, collected_at: Time.current
        )
        metrics_collector = instance_double(SolidQueueAutoscaler::Metrics, collect: metrics)
        allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)

        scaler = SolidQueueAutoscaler::Scaler.new(config: scaler_config)
        result = scaler.run

        # Should scale up despite cooldown being active (only 10s since last scale)
        expect(result.success?).to be(true)
        expect(result.scaled?).to be(true)
        expect(result.decision.action).to eq(:scale_up)
        expect(result.decision.from).to eq(0)
        expect(result.decision.to).to eq(1)
      end

      it 'respects cooldown when scaling from 1+ workers' do
        # At 1 worker (not 0)
        allow(formation_client).to receive(:info).and_return({ 'quantity' => 1 })

        # High queue depth to trigger normal scale up
        metrics = SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 200, oldest_job_age_seconds: 400.0, jobs_per_minute: 0,
          claimed_jobs: 0, failed_jobs: 0, blocked_jobs: 0, active_workers: 1,
          queues_breakdown: { 'default' => 200 }, collected_at: Time.current
        )
        metrics_collector = instance_double(SolidQueueAutoscaler::Metrics, collect: metrics)
        allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)

        scaler = SolidQueueAutoscaler::Scaler.new(config: scaler_config)
        result = scaler.run

        # Should be blocked by cooldown (not at 0 workers)
        expect(result.success?).to be(true)
        expect(result.skipped?).to be(true)
        expect(result.skipped_reason).to include('Cooldown active')
      end
    end
  end
end
