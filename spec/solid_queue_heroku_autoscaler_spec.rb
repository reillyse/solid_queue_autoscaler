# frozen_string_literal: true

RSpec.describe SolidQueueHerokuAutoscaler do
  it 'has a version number' do
    expect(SolidQueueHerokuAutoscaler::VERSION).not_to be_nil
  end

  describe '.configure' do
    it 'yields a configuration object' do
      yielded_config = nil
      described_class.configure do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
        yielded_config = config
      end
      expect(yielded_config).to be_an_instance_of(SolidQueueHerokuAutoscaler::Configuration)
    end

    it 'validates configuration via adapter' do
      expect do
        described_class.configure do |config|
          config.heroku_api_key = nil
        end
      end.to raise_error(SolidQueueHerokuAutoscaler::ConfigurationError)
    end
  end

  describe '.config' do
    it 'returns the configuration' do
      configure_autoscaler
      expect(described_class.config).to be_a(SolidQueueHerokuAutoscaler::Configuration)
    end
  end

  describe '.reset_configuration!' do
    it 'resets the configuration' do
      configure_autoscaler
      described_class.reset_configuration!
      expect(described_class.configuration).to be_nil
    end
  end
end

RSpec.describe SolidQueueHerokuAutoscaler::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'has sensible defaults' do
      expect(config.min_workers).to eq(1)
      expect(config.max_workers).to eq(10)
      expect(config.process_type).to eq('worker')
      expect(config.scale_up_queue_depth).to eq(100)
      expect(config.scale_up_latency_seconds).to eq(300)
      expect(config.scale_down_queue_depth).to eq(10)
      expect(config.cooldown_seconds).to eq(120)
      expect(config.dry_run).to be(false)
      expect(config.enabled).to be(true)
      expect(config.scaling_strategy).to eq(:fixed)
      expect(config.scale_up_jobs_per_worker).to eq(50)
      expect(config.scale_up_latency_per_worker).to eq(60)
      expect(config.scale_down_jobs_per_worker).to eq(50)
    end
  end

  describe '#validate!' do
    it 'raises error when heroku_api_key is missing' do
      config.heroku_api_key = nil
      config.heroku_app_name = 'test-app'
      expect do
        config.validate!
      end.to raise_error(SolidQueueHerokuAutoscaler::ConfigurationError, /heroku_api_key is required/)
    end

    it 'raises error when heroku_app_name is missing' do
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = nil
      expect do
        config.validate!
      end.to raise_error(SolidQueueHerokuAutoscaler::ConfigurationError, /heroku_app_name is required/)
    end

    it 'raises error when min_workers > max_workers' do
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.min_workers = 10
      config.max_workers = 5
      expect do
        config.validate!
      end.to raise_error(SolidQueueHerokuAutoscaler::ConfigurationError,
                         /min_workers cannot exceed max_workers/)
    end

    it 'passes validation with valid config' do
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      expect(config.validate!).to be(true)
    end

    it 'raises error when table_prefix does not end with underscore' do
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.table_prefix = 'my_prefix'
      expect do
        config.validate!
      end.to raise_error(SolidQueueHerokuAutoscaler::ConfigurationError,
                         /table_prefix must end with an underscore/)
    end

    it 'accepts table_prefix ending with underscore' do
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.table_prefix = 'custom_queue_'
      expect(config.validate!).to be(true)
    end

    it 'raises error when table_prefix is nil' do
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.table_prefix = nil
      expect do
        config.validate!
      end.to raise_error(SolidQueueHerokuAutoscaler::ConfigurationError,
                         /table_prefix cannot be nil or empty/)
    end

    it 'raises error when table_prefix is empty string' do
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.table_prefix = ''
      expect do
        config.validate!
      end.to raise_error(SolidQueueHerokuAutoscaler::ConfigurationError,
                         /table_prefix cannot be nil or empty/)
    end

    it 'raises error when table_prefix is only whitespace' do
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.table_prefix = '   '
      expect do
        config.validate!
      end.to raise_error(SolidQueueHerokuAutoscaler::ConfigurationError,
                         /table_prefix cannot be nil or empty/)
    end
  end

  describe '#dry_run?' do
    it 'returns dry_run value' do
      config.dry_run = true
      expect(config.dry_run?).to be(true)
    end
  end

  describe '#enabled?' do
    it 'returns enabled value' do
      config.enabled = false
      expect(config.enabled?).to be(false)
    end
  end

  describe '#adapter' do
    it 'returns default Heroku adapter' do
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      expect(config.adapter).to be_a(SolidQueueHerokuAutoscaler::Adapters::Heroku)
    end

    it 'can be set to a custom adapter class' do
      custom_adapter_class = Class.new(SolidQueueHerokuAutoscaler::Adapters::Base) do
        def current_workers = 1
        def scale(qty) = qty
        def configuration_errors = []
      end
      config.adapter_class = custom_adapter_class
      expect(config.adapter).to be_a(custom_adapter_class)
    end
  end
end

RSpec.describe SolidQueueHerokuAutoscaler::Adapters::Base do
  let(:config) do
    SolidQueueHerokuAutoscaler::Configuration.new.tap do |c|
      c.heroku_api_key = 'test'
      c.heroku_app_name = 'test'
    end
  end

  subject(:adapter) { described_class.new(config: config) }

  describe '#current_workers' do
    it 'raises NotImplementedError' do
      expect { adapter.current_workers }.to raise_error(NotImplementedError)
    end
  end

  describe '#scale' do
    it 'raises NotImplementedError' do
      expect { adapter.scale(1) }.to raise_error(NotImplementedError)
    end
  end

  describe '#name' do
    it 'returns class name' do
      expect(adapter.name).to eq('Base')
    end
  end

  describe '#configured?' do
    it 'returns true when no configuration errors' do
      expect(adapter.configured?).to be(true)
    end
  end

  describe '#configuration_errors' do
    it 'returns empty array by default' do
      expect(adapter.configuration_errors).to eq([])
    end
  end
end

RSpec.describe SolidQueueHerokuAutoscaler::Adapters::Heroku do
  let(:config) do
    SolidQueueHerokuAutoscaler::Configuration.new.tap do |c|
      c.heroku_api_key = 'test-key'
      c.heroku_app_name = 'test-app'
      c.process_type = 'worker'
    end
  end

  subject(:adapter) { described_class.new(config: config) }

  describe '#name' do
    it 'returns Heroku' do
      expect(adapter.name).to eq('Heroku')
    end
  end

  describe '#configuration_errors' do
    context 'with valid config' do
      it 'returns empty array' do
        expect(adapter.configuration_errors).to be_empty
      end
    end

    context 'with missing api key' do
      before { config.heroku_api_key = nil }

      it 'returns error' do
        expect(adapter.configuration_errors).to include('heroku_api_key is required')
      end
    end

    context 'with missing app name' do
      before { config.heroku_app_name = nil }

      it 'returns error' do
        expect(adapter.configuration_errors).to include('heroku_app_name is required')
      end
    end
  end
end

RSpec.describe SolidQueueHerokuAutoscaler::DecisionEngine do
  let(:base_config_options) do
    {
      scale_up_queue_depth: 100,
      scale_up_latency_seconds: 300,
      scale_down_queue_depth: 10,
      scale_down_latency_seconds: 30,
      min_workers: 1,
      max_workers: 10,
      scale_up_increment: 1,
      scale_down_decrement: 1,
      scaling_strategy: :fixed
    }
  end

  let(:config) do
    configure_autoscaler(base_config_options)
    SolidQueueHerokuAutoscaler.config
  end

  subject(:engine) { described_class.new(config: config) }

  let(:idle_metrics) do
    SolidQueueHerokuAutoscaler::Metrics::Result.new(
      queue_depth: 0,
      oldest_job_age_seconds: 0,
      jobs_per_minute: 0,
      claimed_jobs: 0,
      failed_jobs: 0,
      blocked_jobs: 0,
      active_workers: 2,
      queues_breakdown: {},
      collected_at: Time.now
    )
  end

  let(:high_load_metrics) do
    SolidQueueHerokuAutoscaler::Metrics::Result.new(
      queue_depth: 200,
      oldest_job_age_seconds: 400,
      jobs_per_minute: 50,
      claimed_jobs: 5,
      failed_jobs: 0,
      blocked_jobs: 0,
      active_workers: 2,
      queues_breakdown: { 'default' => 200 },
      collected_at: Time.now
    )
  end

  let(:normal_metrics) do
    SolidQueueHerokuAutoscaler::Metrics::Result.new(
      queue_depth: 50,
      oldest_job_age_seconds: 60,
      jobs_per_minute: 20,
      claimed_jobs: 3,
      failed_jobs: 0,
      blocked_jobs: 0,
      active_workers: 2,
      queues_breakdown: { 'default' => 50 },
      collected_at: Time.now
    )
  end

  describe '#decide' do
    context 'when queue is idle and can scale down' do
      it 'returns scale_down decision' do
        decision = engine.decide(metrics: idle_metrics, current_workers: 3)
        expect(decision.action).to eq(:scale_down)
        expect(decision.from).to eq(3)
        expect(decision.to).to eq(2)
      end
    end

    context 'when queue has high load' do
      it 'returns scale_up decision' do
        decision = engine.decide(metrics: high_load_metrics, current_workers: 2)
        expect(decision.action).to eq(:scale_up)
        expect(decision.from).to eq(2)
        expect(decision.to).to eq(3)
      end
    end

    context 'when at max workers' do
      it 'returns no_change decision' do
        decision = engine.decide(metrics: high_load_metrics, current_workers: 10)
        expect(decision.action).to eq(:no_change)
        expect(decision.reason).to include('max_workers')
      end
    end

    context 'when at min workers' do
      it 'returns no_change decision' do
        decision = engine.decide(metrics: idle_metrics, current_workers: 1)
        expect(decision.action).to eq(:no_change)
        expect(decision.reason).to include('min_workers')
      end
    end

    context 'when metrics are within normal range' do
      it 'returns no_change decision' do
        decision = engine.decide(metrics: normal_metrics, current_workers: 3)
        expect(decision.action).to eq(:no_change)
        expect(decision.reason).to include('normal range')
      end
    end

    context 'when autoscaler is disabled' do
      it 'returns no_change decision' do
        config.enabled = false
        decision = engine.decide(metrics: high_load_metrics, current_workers: 2)
        expect(decision.action).to eq(:no_change)
        expect(decision.reason).to eq('Autoscaler is disabled')
      end
    end
  end

  describe 'proportional scaling strategy' do
    let(:config) do
      configure_autoscaler(
        base_config_options.merge(
          scaling_strategy: :proportional,
          scale_up_jobs_per_worker: 50,
          scale_up_latency_per_worker: 60,
          scale_down_jobs_per_worker: 50
        )
      )
      SolidQueueHerokuAutoscaler.config
    end

    let(:very_high_load_metrics) do
      SolidQueueHerokuAutoscaler::Metrics::Result.new(
        queue_depth: 350,              # 250 over threshold (100), should add 5 workers
        oldest_job_age_seconds: 600,   # 300s over threshold, should add 5 workers
        jobs_per_minute: 50,
        claimed_jobs: 5,
        failed_jobs: 0,
        blocked_jobs: 0,
        active_workers: 2,
        queues_breakdown: { 'default' => 350 },
        collected_at: Time.now
      )
    end

    let(:moderate_load_metrics) do
      SolidQueueHerokuAutoscaler::Metrics::Result.new(
        queue_depth: 175,              # 75 over threshold, should add 2 workers
        oldest_job_age_seconds: 350,   # 50s over threshold, should add 1 worker
        jobs_per_minute: 30,
        claimed_jobs: 3,
        failed_jobs: 0,
        blocked_jobs: 0,
        active_workers: 2,
        queues_breakdown: { 'default' => 175 },
        collected_at: Time.now
      )
    end

    let(:low_load_metrics) do
      SolidQueueHerokuAutoscaler::Metrics::Result.new(
        queue_depth: 5,                # 5 under threshold (10)
        oldest_job_age_seconds: 10,
        jobs_per_minute: 10,
        claimed_jobs: 1,
        failed_jobs: 0,
        blocked_jobs: 0,
        active_workers: 5,
        queues_breakdown: { 'default' => 5 },
        collected_at: Time.now
      )
    end

    describe 'scale up' do
      it 'adds multiple workers proportionally based on queue depth' do
        decision = engine.decide(metrics: very_high_load_metrics, current_workers: 2)
        expect(decision.action).to eq(:scale_up)
        expect(decision.from).to eq(2)
        # 250 jobs over threshold / 50 jobs per worker = 5 workers
        # max(5 workers for depth, 5 workers for latency) = 5
        expect(decision.to).to eq(7)
        expect(decision.reason).to include('proportional')
        expect(decision.reason).to include('+5 workers')
      end

      it 'adds workers based on the higher of depth or latency calculation' do
        decision = engine.decide(metrics: moderate_load_metrics, current_workers: 2)
        expect(decision.action).to eq(:scale_up)
        # 75 jobs over threshold / 50 = 2 workers (ceil)
        # 50s over threshold / 60 = 1 worker (ceil)
        # max(2, 1) = 2 workers to add
        expect(decision.to).to eq(4)
      end

      it 'respects max_workers limit' do
        decision = engine.decide(metrics: very_high_load_metrics, current_workers: 8)
        expect(decision.action).to eq(:scale_up)
        expect(decision.to).to eq(10) # max_workers
      end

      it 'adds at least scale_up_increment even with small overage' do
        small_overage_metrics = SolidQueueHerokuAutoscaler::Metrics::Result.new(
          queue_depth: 105, # Only 5 jobs over threshold
          oldest_job_age_seconds: 305,
          jobs_per_minute: 10,
          claimed_jobs: 1,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 2,
          queues_breakdown: { 'default' => 105 },
          collected_at: Time.now
        )
        decision = engine.decide(metrics: small_overage_metrics, current_workers: 2)
        expect(decision.action).to eq(:scale_up)
        expect(decision.to).to be >= 3 # At least 1 worker added
      end
    end

    describe 'scale down' do
      it 'removes workers proportionally' do
        decision = engine.decide(metrics: low_load_metrics, current_workers: 5)
        expect(decision.action).to eq(:scale_down)
        expect(decision.from).to eq(5)
        expect(decision.to).to eq(4)
        expect(decision.reason).to include('proportional')
      end

      it 'scales to min_workers when idle' do
        decision = engine.decide(metrics: idle_metrics, current_workers: 5)
        expect(decision.action).to eq(:scale_down)
        expect(decision.to).to eq(1) # min_workers
      end

      it 'respects min_workers limit' do
        decision = engine.decide(metrics: low_load_metrics, current_workers: 2)
        expect(decision.action).to eq(:scale_down)
        expect(decision.to).to be >= 1 # min_workers
      end
    end
  end

  describe 'fixed scaling strategy (default)' do
    it 'adds fixed increment regardless of load level' do
      decision = engine.decide(metrics: high_load_metrics, current_workers: 2)
      expect(decision.action).to eq(:scale_up)
      expect(decision.to).to eq(3)  # Just +1
    end

    it 'removes fixed decrement regardless of load level' do
      decision = engine.decide(metrics: idle_metrics, current_workers: 5)
      expect(decision.action).to eq(:scale_down)
      expect(decision.to).to eq(4)  # Just -1
    end
  end
end
