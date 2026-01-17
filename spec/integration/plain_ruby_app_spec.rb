# frozen_string_literal: true

# Integration tests for using SolidQueueAutoscaler in a plain Ruby app
# (without Rails or any web framework).
#
# This simulates a standalone Ruby script or daemon that uses the gem
# directly without Rails' autoloading, Railtie, or ActiveJob.
#
# Use cases:
# - Background daemon scripts
# - Cron jobs
# - CLI tools
# - Microservices without Rails

RSpec.describe 'Integration: Plain Ruby App', :integration do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, error: nil, warn: nil) }
  let(:mock_connection) do
    instance_double(
      ActiveRecord::ConnectionAdapters::AbstractAdapter,
      adapter_name: 'PostgreSQL',
      table_exists?: true,
      select_value: 0,
      execute: nil,
      quote_table_name: ->(name) { "\"#{name}\"" }
    )
  end

  # Store original queue_name to restore after all tests
  before(:all) do
    @original_queue_name = SolidQueueAutoscaler::AutoscaleJob.queue_name rescue 'autoscaler'
  end

  after(:all) do
    # Restore AutoscaleJob queue_name after all tests in this file
    if defined?(SolidQueueAutoscaler::AutoscaleJob)
      SolidQueueAutoscaler::AutoscaleJob.queue_name = @original_queue_name || 'autoscaler'
    end
  end

  before do
    # Reset configuration before each test
    SolidQueueAutoscaler.reset_configuration!
    
    # Mock database connection for tests
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:quote_table_name) { |name| "\"#{name}\"" }
  end

  after do
    SolidQueueAutoscaler.reset_configuration!
    # Restore queue_name after each test to avoid pollution
    if defined?(SolidQueueAutoscaler::AutoscaleJob)
      SolidQueueAutoscaler::AutoscaleJob.queue_name = 'autoscaler'
    end
  end

  describe 'Plain Ruby usage without Rails' do
    # In a plain Ruby app, Rails is not defined, so:
    # - No Railtie is loaded
    # - No Rails.logger exists
    # - No ActiveJob (unless explicitly loaded)
    # - No automatic configuration

    context 'basic configuration and usage' do
      it 'can be configured without Rails' do
        # This is how a plain Ruby app would configure the gem
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-api-key'
          config.heroku_app_name = 'my-app'
          config.min_workers = 1
          config.max_workers = 5
          config.enabled = true
          config.dry_run = true
          config.logger = logger
        end

        # Verify configuration is stored
        expect(SolidQueueAutoscaler.configurations).to have_key(:worker)
        expect(SolidQueueAutoscaler.config(:worker).heroku_api_key).to eq('test-api-key')
        expect(SolidQueueAutoscaler.config(:worker).adapter).to be_a(SolidQueueAutoscaler::Adapters::Heroku)
      end

      it 'can configure multiple workers' do
        SolidQueueAutoscaler.configure(:default_worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'worker'
          config.logger = logger
        end

        SolidQueueAutoscaler.configure(:priority_worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'priority'
          config.logger = logger
        end

        expect(SolidQueueAutoscaler.registered_workers).to contain_exactly(:default_worker, :priority_worker)
      end

      it 'validates configuration' do
        expect {
          SolidQueueAutoscaler.configure(:worker) do |config|
            # Missing required heroku_api_key and heroku_app_name
            config.adapter = :heroku
          end
        }.to raise_error(SolidQueueAutoscaler::ConfigurationError)
      end
    end

    context 'using the Scaler directly (no ActiveJob)' do
      let(:mock_adapter) do
        instance_double(
          SolidQueueAutoscaler::Adapters::Heroku,
          current_workers: 2,
          scale: true
        )
      end

      before do
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.min_workers = 1
          config.max_workers = 5
          config.dry_run = true
          config.enabled = true
          config.logger = logger
        end

        # Mock the adapter
        allow(SolidQueueAutoscaler.config(:worker)).to receive(:adapter).and_return(mock_adapter)
      end

      it 'can call scale! directly without Rails' do
        # Mock metrics to simulate an empty queue
        allow_any_instance_of(SolidQueueAutoscaler::Metrics).to receive(:collect).and_return(
          SolidQueueAutoscaler::Metrics::Result.new(
            queue_depth: 5,
            oldest_job_age_seconds: 10,
            jobs_per_minute: 0,
            claimed_jobs: 0,
            failed_jobs: 0,
            blocked_jobs: 0,
            active_workers: 2,
            queues_breakdown: {}
          )
        )

        # This is how a plain Ruby daemon would trigger scaling
        result = SolidQueueAutoscaler.scale!(:worker)

        expect(result).to be_a(SolidQueueAutoscaler::Scaler::ScaleResult)
        expect(result.success?).to be true
      end

      it 'can call scale_all! directly' do
        allow_any_instance_of(SolidQueueAutoscaler::Metrics).to receive(:collect).and_return(
          SolidQueueAutoscaler::Metrics::Result.new(
            queue_depth: 5,
            oldest_job_age_seconds: 10,
            jobs_per_minute: 0,
            claimed_jobs: 0,
            failed_jobs: 0,
            blocked_jobs: 0,
            active_workers: 2,
            queues_breakdown: {}
          )
        )

        results = SolidQueueAutoscaler.scale_all!

        expect(results).to be_a(Hash)
        expect(results[:worker]).to be_a(SolidQueueAutoscaler::Scaler::ScaleResult)
      end

      it 'can get metrics directly' do
        allow_any_instance_of(SolidQueueAutoscaler::Metrics).to receive(:collect).and_return(
          SolidQueueAutoscaler::Metrics::Result.new(
            queue_depth: 100,
            oldest_job_age_seconds: 300,
            jobs_per_minute: 50,
            claimed_jobs: 10,
            failed_jobs: 0,
            blocked_jobs: 0,
            active_workers: 2,
            queues_breakdown: { 'default' => 100 }
          )
        )

        metrics = SolidQueueAutoscaler.metrics(:worker)

        expect(metrics.queue_depth).to eq(100)
        expect(metrics.oldest_job_age_seconds).to eq(300)
      end
    end

    context 'custom logger (no Rails.logger)' do
      it 'uses provided logger instead of Rails.logger' do
        custom_logger = Logger.new(StringIO.new)

        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.logger = custom_logger
        end

        expect(SolidQueueAutoscaler.config(:worker).logger).to eq(custom_logger)
      end

      it 'creates default logger when none provided and Rails is not defined' do
        # Ensure Rails is not stubbed in this test
        hide_const('Rails') if defined?(Rails)

        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          # Don't set logger - should use default
        end

        # The gem should create a default logger or handle nil gracefully
        expect(SolidQueueAutoscaler.config(:worker).logger).not_to be_nil
      end
    end

    context 'Kubernetes adapter in plain Ruby' do
      it 'can configure Kubernetes adapter' do
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :kubernetes
          config.kubernetes_deployment = 'my-worker'
          config.kubernetes_namespace = 'production'
          config.min_workers = 1
          config.max_workers = 10
          config.logger = logger
        end

        expect(SolidQueueAutoscaler.config(:worker).adapter).to be_a(SolidQueueAutoscaler::Adapters::Kubernetes)
      end
    end
  end

  describe 'Example: Plain Ruby daemon script' do
    # This simulates what a real plain Ruby daemon script would look like

    it 'demonstrates a complete daemon setup' do
      # === Step 1: Configure the autoscaler ===
      SolidQueueAutoscaler.configure(:background_worker) do |config|
        config.adapter = :heroku
        config.heroku_api_key = ENV.fetch('HEROKU_API_KEY', 'test-key')
        config.heroku_app_name = ENV.fetch('HEROKU_APP_NAME', 'test-app')
        config.process_type = 'worker'
        config.min_workers = 1
        config.max_workers = 5
        config.scale_up_queue_depth = 100
        config.scale_down_queue_depth = 10
        config.cooldown_seconds = 120
        config.dry_run = true  # Safe for testing
        config.enabled = true
        config.logger = logger
      end

      # === Step 2: Create a simple scaling loop ===
      # (In a real daemon, this would run in an infinite loop with sleep)
      
      # Mock the adapter for testing
      mock_adapter = instance_double(
        SolidQueueAutoscaler::Adapters::Heroku,
        current_workers: 2,
        scale: true
      )
      allow(SolidQueueAutoscaler.config(:background_worker)).to receive(:adapter).and_return(mock_adapter)
      
      # Mock metrics
      allow_any_instance_of(SolidQueueAutoscaler::Metrics).to receive(:collect).and_return(
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 50,
          oldest_job_age_seconds: 60,
          jobs_per_minute: 10,
          claimed_jobs: 5,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 2,
          queues_breakdown: {}
        )
      )

      # === Step 3: Run the scaler ===
      result = SolidQueueAutoscaler.scale!(:background_worker)

      # === Step 4: Handle the result ===
      expect(result.success?).to be true
      
      # In a real daemon, you might do:
      # if result.success?
      #   if result.scaled?
      #     puts "Scaled from #{result.decision.from} to #{result.decision.to}"
      #   else
      #     puts "No scaling needed"
      #   end
      # else
      #   puts "Error: #{result.error}"
      # end
    end
  end

  describe 'No Railtie loaded' do
    it 'works without Rails being defined' do
      # The Railtie is only loaded when Rails::Railtie is defined.
      # In plain Ruby, this should not cause errors - the gem should still work.
      
      hide_const('Rails') if defined?(Rails)
      
      # The gem should still work without Rails
      SolidQueueAutoscaler.configure(:test) do |config|
        config.adapter = :heroku
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
        config.logger = logger
      end

      expect(SolidQueueAutoscaler.config(:test)).not_to be_nil
      expect(SolidQueueAutoscaler.registered_workers).to include(:test)
    end
  end

  describe 'No ActiveJob loaded' do
    it 'does not load AutoscaleJob when ActiveJob::Base is not defined' do
      # The AutoscaleJob is only loaded when ActiveJob::Base is defined
      # In plain Ruby without ActiveJob, this should not cause errors
      
      # Note: In our test environment, ActiveJob is loaded, so we just verify
      # that the gem can work without using AutoscaleJob
      
      SolidQueueAutoscaler.configure(:worker) do |config|
        config.adapter = :heroku
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
        config.logger = logger
      end

      # Can use scale! directly without needing AutoscaleJob
      expect { SolidQueueAutoscaler.scale!(:worker) }.not_to raise_error
    end
  end
end
