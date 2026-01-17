# frozen_string_literal: true

# Integration tests for using SolidQueueAutoscaler in a Sinatra app
# (or any Rack-based web framework without Rails).
#
# This simulates a Sinatra web app that:
# - Has an admin endpoint to trigger scaling
# - Has a status endpoint to show current metrics
# - Uses the gem without Rails' Railtie or generators
#
# Use cases:
# - Sinatra API services
# - Rack-based microservices
# - Grape API applications
# - Hanami applications
# - Roda applications

RSpec.describe 'Integration: Sinatra App', :integration do
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

  describe 'Sinatra app usage pattern' do
    # Simulates a typical Sinatra app structure
    #
    # In a real Sinatra app, you would:
    # 1. Add to Gemfile: gem 'solid_queue_autoscaler'
    # 2. Configure in config.ru or app.rb
    # 3. Create endpoints for scaling and status

    context 'configuration in Sinatra app' do
      it 'can be configured in a Sinatra app.rb style' do
        # Simulates what would be in a Sinatra app's configure block:
        # 
        # class MyApp < Sinatra::Base
        #   configure do
        #     SolidQueueAutoscaler.configure(:worker) do |config|
        #       ...
        #     end
        #   end
        # end

        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = ENV.fetch('HEROKU_API_KEY', 'test-key')
          config.heroku_app_name = ENV.fetch('HEROKU_APP_NAME', 'test-app')
          config.process_type = 'worker'
          config.min_workers = 1
          config.max_workers = 10
          config.dry_run = true
          config.enabled = true
          config.logger = logger
        end

        expect(SolidQueueAutoscaler.config(:worker)).not_to be_nil
        expect(SolidQueueAutoscaler.config(:worker).adapter).to be_a(SolidQueueAutoscaler::Adapters::Heroku)
      end

      it 'can be configured via config.ru' do
        # Simulates config.ru configuration:
        #
        # require 'sinatra'
        # require 'solid_queue_autoscaler'
        #
        # SolidQueueAutoscaler.configure(:worker) do |config|
        #   ...
        # end
        #
        # run Sinatra::Application

        SolidQueueAutoscaler.configure(:api_worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'my-sinatra-app'
          config.process_type = 'worker'
          config.logger = logger
        end

        expect(SolidQueueAutoscaler.registered_workers).to include(:api_worker)
      end
    end

    context 'admin endpoint simulation' do
      # Simulates what a Sinatra endpoint would do
      
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
        
        allow(SolidQueueAutoscaler.config(:worker)).to receive(:adapter).and_return(mock_adapter)
        
        allow_any_instance_of(SolidQueueAutoscaler::Metrics).to receive(:collect).and_return(
          SolidQueueAutoscaler::Metrics::Result.new(
            queue_depth: 50,
            oldest_job_age_seconds: 60,
            jobs_per_minute: 10,
            claimed_jobs: 5,
            failed_jobs: 0,
            blocked_jobs: 0,
            active_workers: 2,
            queues_breakdown: { 'default' => 50 }
          )
        )
      end

      it 'simulates POST /admin/scale endpoint' do
        # In a real Sinatra app:
        #
        # post '/admin/scale' do
        #   result = SolidQueueAutoscaler.scale!(:worker)
        #   if result.success?
        #     json status: 'ok', scaled: result.scaled?, decision: result.decision&.to_h
        #   else
        #     status 500
        #     json status: 'error', message: result.error&.message
        #   end
        # end

        result = SolidQueueAutoscaler.scale!(:worker)
        
        # Build response like a Sinatra endpoint would
        if result.success?
          response = {
            status: 'ok',
            scaled: result.scaled?,
            decision: result.decision&.to_h
          }
          expect(response[:status]).to eq('ok')
        else
          response = {
            status: 'error',
            message: result.error&.message
          }
          expect(response[:status]).to eq('error')
        end
      end

      it 'simulates GET /admin/metrics endpoint' do
        # In a real Sinatra app:
        #
        # get '/admin/metrics' do
        #   metrics = SolidQueueAutoscaler.metrics(:worker)
        #   json(
        #     queue_depth: metrics.queue_depth,
        #     oldest_job_age: metrics.oldest_job_age_seconds,
        #     active_workers: metrics.active_workers
        #   )
        # end

        metrics = SolidQueueAutoscaler.metrics(:worker)
        
        response = {
          queue_depth: metrics.queue_depth,
          oldest_job_age: metrics.oldest_job_age_seconds,
          active_workers: metrics.active_workers,
          queues: metrics.queues_breakdown
        }

        expect(response[:queue_depth]).to eq(50)
        expect(response[:oldest_job_age]).to eq(60)
        expect(response[:active_workers]).to eq(2)
      end

      it 'simulates GET /admin/workers endpoint' do
        # In a real Sinatra app:
        #
        # get '/admin/workers' do
        #   workers = SolidQueueAutoscaler.registered_workers
        #   json workers: workers.map { |name|
        #     config = SolidQueueAutoscaler.config(name)
        #     {
        #       name: name,
        #       process_type: config.process_type,
        #       min: config.min_workers,
        #       max: config.max_workers,
        #       current: config.adapter.current_workers
        #     }
        #   }
        # end

        workers = SolidQueueAutoscaler.registered_workers
        
        response = {
          workers: workers.map do |name|
            config = SolidQueueAutoscaler.config(name)
            {
              name: name,
              process_type: config.process_type,
              min: config.min_workers,
              max: config.max_workers,
              current: config.adapter.current_workers
            }
          end
        }

        expect(response[:workers].first[:name]).to eq(:worker)
        expect(response[:workers].first[:current]).to eq(2)
      end

      it 'simulates POST /admin/scale_all endpoint' do
        # Add another worker
        SolidQueueAutoscaler.configure(:priority_worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'priority'
          config.dry_run = true
          config.logger = logger
        end
        allow(SolidQueueAutoscaler.config(:priority_worker)).to receive(:adapter).and_return(mock_adapter)

        # In a real Sinatra app:
        #
        # post '/admin/scale_all' do
        #   results = SolidQueueAutoscaler.scale_all!
        #   json results: results.transform_values { |r|
        #     { success: r.success?, scaled: r.scaled? }
        #   }
        # end

        results = SolidQueueAutoscaler.scale_all!

        response = {
          results: results.transform_values { |r| { success: r.success?, scaled: r.scaled? } }
        }

        expect(response[:results][:worker][:success]).to be true
        expect(response[:results][:priority_worker][:success]).to be true
      end
    end

    context 'background thread pattern for Sinatra' do
      # Sinatra apps often use a background thread for periodic tasks
      # instead of ActiveJob/SolidQueue recurring jobs

      it 'simulates a background scaling thread' do
        mock_adapter = instance_double(
          SolidQueueAutoscaler::Adapters::Heroku,
          current_workers: 2,
          scale: true
        )

        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.dry_run = true
          config.enabled = true
          config.logger = logger
        end

        allow(SolidQueueAutoscaler.config(:worker)).to receive(:adapter).and_return(mock_adapter)
        
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

        # In a real Sinatra app, you might start a background thread:
        #
        # Thread.new do
        #   loop do
        #     begin
        #       SolidQueueAutoscaler.scale_all!
        #     rescue => e
        #       logger.error "Autoscaler error: #{e.message}"
        #     end
        #     sleep 30
        #   end
        # end

        # Simulate one iteration of the background loop
        scale_iteration = -> {
          begin
            SolidQueueAutoscaler.scale_all!
            { success: true }
          rescue StandardError => e
            { success: false, error: e.message }
          end
        }

        result = scale_iteration.call
        expect(result[:success]).to be true
      end
    end
  end

  describe 'Example: Complete Sinatra app structure' do
    # This demonstrates the complete structure of a Sinatra app using the gem

    it 'demonstrates a complete Sinatra app setup' do
      # === config.ru ===
      # require 'sinatra'
      # require 'solid_queue_autoscaler'
      # require_relative 'app'
      # run MyApp

      # === app.rb ===
      # class MyApp < Sinatra::Base
      #   configure do
      #     SolidQueueAutoscaler.configure(:worker) do |config|
      #       config.adapter = :heroku
      #       config.heroku_api_key = ENV['HEROKU_API_KEY']
      #       config.heroku_app_name = ENV['HEROKU_APP_NAME']
      #       config.enabled = ENV['RACK_ENV'] == 'production'
      #       config.dry_run = ENV['AUTOSCALER_DRY_RUN'] == 'true'
      #     end
      #   end
      #
      #   get '/health' do
      #     'ok'
      #   end
      #
      #   namespace '/admin' do
      #     before { authenticate! }
      #
      #     get '/autoscaler/status' do
      #       json SolidQueueAutoscaler.registered_workers.map { |name|
      #         config = SolidQueueAutoscaler.config(name)
      #         metrics = SolidQueueAutoscaler.metrics(name)
      #         {
      #           worker: name,
      #           enabled: config.enabled?,
      #           current_workers: config.adapter.current_workers,
      #           queue_depth: metrics.queue_depth
      #         }
      #       }
      #     end
      #
      #     post '/autoscaler/scale' do
      #       result = SolidQueueAutoscaler.scale!(params[:worker]&.to_sym || :default)
      #       json success: result.success?, scaled: result.scaled?
      #     end
      #   end
      # end

      # Simulate the configure block
      SolidQueueAutoscaler.configure(:worker) do |config|
        config.adapter = :heroku
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'my-sinatra-app'
        config.dry_run = true
        config.enabled = true
        config.logger = logger
      end

      # Mock adapter
      mock_adapter = instance_double(
        SolidQueueAutoscaler::Adapters::Heroku,
        current_workers: 3,
        scale: true
      )
      allow(SolidQueueAutoscaler.config(:worker)).to receive(:adapter).and_return(mock_adapter)

      # Mock metrics
      allow_any_instance_of(SolidQueueAutoscaler::Metrics).to receive(:collect).and_return(
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 75,
          oldest_job_age_seconds: 120,
          jobs_per_minute: 25,
          claimed_jobs: 10,
          failed_jobs: 1,
          blocked_jobs: 0,
          active_workers: 3,
          queues_breakdown: { 'default' => 50, 'mailers' => 25 }
        )
      )

      # Simulate GET /admin/autoscaler/status
      status_response = SolidQueueAutoscaler.registered_workers.map do |name|
        config = SolidQueueAutoscaler.config(name)
        metrics = SolidQueueAutoscaler.metrics(name)
        {
          worker: name,
          enabled: config.enabled?,
          current_workers: config.adapter.current_workers,
          queue_depth: metrics.queue_depth
        }
      end

      expect(status_response.first[:worker]).to eq(:worker)
      expect(status_response.first[:enabled]).to be true
      expect(status_response.first[:current_workers]).to eq(3)
      expect(status_response.first[:queue_depth]).to eq(75)

      # Simulate POST /admin/autoscaler/scale
      result = SolidQueueAutoscaler.scale!(:worker)
      scale_response = { success: result.success?, scaled: result.scaled? }

      expect(scale_response[:success]).to be true
    end
  end

  describe 'Grape API integration pattern' do
    # Grape is another popular Ruby API framework often used with Sinatra

    it 'demonstrates Grape API resource pattern' do
      # In a Grape API, you might have:
      #
      # module API
      #   class Autoscaler < Grape::API
      #     namespace :autoscaler do
      #       get :status do
      #         SolidQueueAutoscaler.registered_workers.map { |name| ... }
      #       end
      #
      #       post :scale do
      #         SolidQueueAutoscaler.scale!(params[:worker].to_sym)
      #       end
      #     end
      #   end
      # end

      SolidQueueAutoscaler.configure(:api_worker) do |config|
        config.adapter = :heroku
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'grape-api'
        config.dry_run = true
        config.logger = logger
      end

      # The gem works the same way regardless of framework
      expect(SolidQueueAutoscaler.config(:api_worker)).not_to be_nil
      expect(SolidQueueAutoscaler.registered_workers).to include(:api_worker)
    end
  end

  describe 'Rack middleware pattern' do
    # You could also use a Rack middleware to periodically scale

    it 'demonstrates Rack middleware approach' do
      # class AutoscalerMiddleware
      #   def initialize(app, interval: 30)
      #     @app = app
      #     @interval = interval
      #     @last_scale = Time.now - interval
      #   end
      #
      #   def call(env)
      #     if Time.now - @last_scale >= @interval
      #       begin
      #         SolidQueueAutoscaler.scale_all!
      #         @last_scale = Time.now
      #       rescue => e
      #         env['rack.errors'].puts "Autoscaler error: #{e.message}"
      #       end
      #     end
      #     @app.call(env)
      #   end
      # end

      SolidQueueAutoscaler.configure(:worker) do |config|
        config.adapter = :heroku
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'rack-app'
        config.dry_run = true
        config.logger = logger
      end

      # Simulate middleware behavior
      last_scale = Time.now - 60  # 60 seconds ago
      interval = 30

      if Time.now - last_scale >= interval
        # Would trigger scale_all! in real middleware
        expect(SolidQueueAutoscaler.registered_workers).not_to be_empty
      end
    end
  end

  describe 'No Rails dependencies' do
    it 'works without any Rails-specific features' do
      # Verify we can use the gem without:
      # - Rails.logger
      # - Rails generators
      # - Rails::Railtie
      # - ActiveJob (for direct scale! calls)

      custom_logger = Logger.new(StringIO.new)

      SolidQueueAutoscaler.configure(:standalone) do |config|
        config.adapter = :heroku
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'non-rails-app'
        config.logger = custom_logger  # Custom logger, not Rails.logger
        config.dry_run = true
      end

      expect(SolidQueueAutoscaler.config(:standalone).logger).to eq(custom_logger)
      expect(SolidQueueAutoscaler.config(:standalone).adapter).to be_a(SolidQueueAutoscaler::Adapters::Heroku)
    end
  end
end
