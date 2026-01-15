# frozen_string_literal: true

RSpec.describe 'Multi-worker configuration support' do
  before do
    SolidQueueHerokuAutoscaler.reset_configuration!
  end

  describe 'SolidQueueHerokuAutoscaler.configure' do
    context 'with default name (backward compatibility)' do
      it 'creates a default configuration' do
        SolidQueueHerokuAutoscaler.configure do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
        end

        expect(SolidQueueHerokuAutoscaler.config.name).to eq(:default)
        expect(SolidQueueHerokuAutoscaler.config.heroku_api_key).to eq('test-key')
      end

      it 'is accessible via .configuration for backward compatibility' do
        SolidQueueHerokuAutoscaler.configure do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
        end

        expect(SolidQueueHerokuAutoscaler.configuration).to eq(SolidQueueHerokuAutoscaler.config(:default))
      end
    end

    context 'with named configurations' do
      it 'creates separate configurations for different worker types' do
        SolidQueueHerokuAutoscaler.configure(:critical_worker) do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'critical_worker'
          config.queues = ['critical']
          config.max_workers = 5
        end

        SolidQueueHerokuAutoscaler.configure(:default_worker) do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'worker'
          config.queues = %w[default mailers]
          config.max_workers = 10
        end

        critical = SolidQueueHerokuAutoscaler.config(:critical_worker)
        default = SolidQueueHerokuAutoscaler.config(:default_worker)

        expect(critical.name).to eq(:critical_worker)
        expect(critical.process_type).to eq('critical_worker')
        expect(critical.queues).to eq(['critical'])
        expect(critical.max_workers).to eq(5)

        expect(default.name).to eq(:default_worker)
        expect(default.process_type).to eq('worker')
        expect(default.queues).to eq(%w[default mailers])
        expect(default.max_workers).to eq(10)
      end

      it 'generates unique lock keys per configuration' do
        SolidQueueHerokuAutoscaler.configure(:critical_worker) do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
        end

        SolidQueueHerokuAutoscaler.configure(:default_worker) do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
        end

        critical = SolidQueueHerokuAutoscaler.config(:critical_worker)
        default = SolidQueueHerokuAutoscaler.config(:default_worker)

        expect(critical.lock_key).to eq('solid_queue_autoscaler_critical_worker')
        expect(default.lock_key).to eq('solid_queue_autoscaler_default_worker')
        expect(critical.lock_key).not_to eq(default.lock_key)
      end

      it 'allows custom lock_key to override auto-generated one' do
        SolidQueueHerokuAutoscaler.configure(:critical_worker) do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.lock_key = 'my_custom_lock'
        end

        expect(SolidQueueHerokuAutoscaler.config(:critical_worker).lock_key).to eq('my_custom_lock')
      end
    end
  end

  describe 'SolidQueueHerokuAutoscaler.registered_workers' do
    it 'returns empty array when no configurations exist' do
      expect(SolidQueueHerokuAutoscaler.registered_workers).to eq([])
    end

    it 'returns all configured worker names' do
      SolidQueueHerokuAutoscaler.configure(:critical_worker) do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
      end

      SolidQueueHerokuAutoscaler.configure(:default_worker) do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
      end

      expect(SolidQueueHerokuAutoscaler.registered_workers).to contain_exactly(:critical_worker, :default_worker)
    end
  end

  describe 'SolidQueueHerokuAutoscaler.reset_configuration!' do
    it 'clears all configurations' do
      SolidQueueHerokuAutoscaler.configure(:critical_worker) do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
      end

      SolidQueueHerokuAutoscaler.reset_configuration!

      expect(SolidQueueHerokuAutoscaler.registered_workers).to eq([])
      expect(SolidQueueHerokuAutoscaler.configurations).to eq({})
    end
  end

  describe 'Configuration#name' do
    it 'defaults to :default' do
      config = SolidQueueHerokuAutoscaler::Configuration.new
      expect(config.name).to eq(:default)
    end

    it 'is set automatically when using named configure' do
      SolidQueueHerokuAutoscaler.configure(:my_worker) do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
      end

      expect(SolidQueueHerokuAutoscaler.config(:my_worker).name).to eq(:my_worker)
    end
  end

  describe 'Configuration#lock_key' do
    it 'generates lock key based on name when not explicitly set' do
      config = SolidQueueHerokuAutoscaler::Configuration.new
      config.name = :critical_worker

      expect(config.lock_key).to eq('solid_queue_autoscaler_critical_worker')
    end

    it 'uses default name when name is :default' do
      config = SolidQueueHerokuAutoscaler::Configuration.new
      expect(config.lock_key).to eq('solid_queue_autoscaler_default')
    end

    it 'allows explicit lock_key to override generated one' do
      config = SolidQueueHerokuAutoscaler::Configuration.new
      config.name = :critical_worker
      config.lock_key = 'custom_lock'

      expect(config.lock_key).to eq('custom_lock')
    end
  end
end

RSpec.describe 'Scaler per-configuration cooldowns' do
  before do
    SolidQueueHerokuAutoscaler.reset_configuration!
    SolidQueueHerokuAutoscaler::Scaler.reset_cooldowns!
  end

  describe 'cooldown tracking' do
    it 'tracks cooldowns separately per configuration name' do
      time1 = Time.current
      time2 = Time.current + 10.seconds

      SolidQueueHerokuAutoscaler::Scaler.set_last_scale_up_at(:critical_worker, time1)
      SolidQueueHerokuAutoscaler::Scaler.set_last_scale_up_at(:default_worker, time2)

      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at(:critical_worker)).to eq(time1)
      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at(:default_worker)).to eq(time2)
    end

    it 'tracks scale down separately from scale up' do
      time1 = Time.current
      time2 = Time.current + 10.seconds

      SolidQueueHerokuAutoscaler::Scaler.set_last_scale_up_at(:worker, time1)
      SolidQueueHerokuAutoscaler::Scaler.set_last_scale_down_at(:worker, time2)

      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at(:worker)).to eq(time1)
      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_down_at(:worker)).to eq(time2)
    end

    it 'returns nil for unset cooldowns' do
      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at(:nonexistent)).to be_nil
      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_down_at(:nonexistent)).to be_nil
    end

    it 'resets cooldowns for a specific configuration' do
      SolidQueueHerokuAutoscaler::Scaler.set_last_scale_up_at(:worker1, Time.current)
      SolidQueueHerokuAutoscaler::Scaler.set_last_scale_up_at(:worker2, Time.current)

      SolidQueueHerokuAutoscaler::Scaler.reset_cooldowns!(:worker1)

      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at(:worker1)).to be_nil
      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at(:worker2)).not_to be_nil
    end

    it 'resets all cooldowns when no name provided' do
      SolidQueueHerokuAutoscaler::Scaler.set_last_scale_up_at(:worker1, Time.current)
      SolidQueueHerokuAutoscaler::Scaler.set_last_scale_up_at(:worker2, Time.current)

      SolidQueueHerokuAutoscaler::Scaler.reset_cooldowns!

      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at(:worker1)).to be_nil
      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at(:worker2)).to be_nil
    end
  end

  describe 'backward compatibility' do
    it 'supports assignment operators for default configuration' do
      time = Time.current
      SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at = time

      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at(:default)).to eq(time)
    end

    it 'supports reading default configuration without name' do
      time = Time.current
      SolidQueueHerokuAutoscaler::Scaler.set_last_scale_up_at(:default, time)

      expect(SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at).to eq(time)
    end
  end
end

RSpec.describe 'scale_all!' do
  let(:mock_adapter1) do
    instance_double(
      SolidQueueHerokuAutoscaler::Adapters::Heroku,
      current_workers: 2,
      scale: true,
      name: 'Heroku',
      configuration_errors: []
    )
  end

  let(:mock_adapter2) do
    instance_double(
      SolidQueueHerokuAutoscaler::Adapters::Heroku,
      current_workers: 3,
      scale: true,
      name: 'Heroku',
      configuration_errors: []
    )
  end

  before do
    SolidQueueHerokuAutoscaler.reset_configuration!

    SolidQueueHerokuAutoscaler.configure(:critical_worker) do |config|
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.process_type = 'critical_worker'
      config.enabled = false # Disable to avoid real scaling
    end

    SolidQueueHerokuAutoscaler.configure(:default_worker) do |config|
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.process_type = 'worker'
      config.enabled = false
    end
  end

  it 'returns empty hash when no configurations exist' do
    SolidQueueHerokuAutoscaler.reset_configuration!
    expect(SolidQueueHerokuAutoscaler.scale_all!).to eq({})
  end

  it 'scales all configured workers' do
    results = SolidQueueHerokuAutoscaler.scale_all!

    expect(results.keys).to contain_exactly(:critical_worker, :default_worker)
    expect(results[:critical_worker]).to be_a(SolidQueueHerokuAutoscaler::Scaler::ScaleResult)
    expect(results[:default_worker]).to be_a(SolidQueueHerokuAutoscaler::Scaler::ScaleResult)
  end

  it 'returns skipped results when disabled' do
    results = SolidQueueHerokuAutoscaler.scale_all!

    expect(results[:critical_worker].skipped?).to be(true)
    expect(results[:critical_worker].skipped_reason).to include('disabled')
    expect(results[:default_worker].skipped?).to be(true)
  end
end
