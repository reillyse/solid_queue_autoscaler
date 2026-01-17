# frozen_string_literal: true

# Load ActiveJob for testing AutoscaleJob
require 'active_job'
require 'active_job/test_helper'
require_relative '../lib/solid_queue_autoscaler/autoscale_job'

RSpec.describe SolidQueueAutoscaler::AutoscaleJob do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, error: nil, warn: nil) }

  before do
    allow_any_instance_of(described_class).to receive(:logger).and_return(logger)
    stub_const('Rails', double('Rails', logger: logger))
    SolidQueueAutoscaler.reset_configuration!
    # Reset the job queue_name to default for each test (use string, as ActiveJob expects)
    described_class.queue_name = 'autoscaler'
  end

  after do
    # Reset after each test to avoid polluting other tests
    described_class.queue_name = 'autoscaler'
  end

  describe 'job_queue configuration' do
    describe 'class-level queue_name' do
      it 'uses the configured job_queue after apply_job_settings!' do
        # Configure with a custom queue
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.job_queue = :my_custom_queue
          config.logger = logger
        end

        # Apply job settings (normally called by railtie after_initialize)
        SolidQueueAutoscaler.apply_job_settings!

        # queue_name is converted to string since ActiveJob uses strings internally
        expect(described_class.queue_name).to eq('my_custom_queue')
      end

      it 'defaults to autoscaler when job_queue is not set' do
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.logger = logger
          # job_queue defaults to :autoscaler in Configuration
        end

        SolidQueueAutoscaler.apply_job_settings!

        expect(described_class.queue_name).to eq('autoscaler')
      end

      it 'uses the first configured worker\'s job_queue with multiple workers' do
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.job_queue = :first_queue
          config.logger = logger
        end

        SolidQueueAutoscaler.configure(:priority_worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.job_queue = :second_queue
          config.logger = logger
        end

        SolidQueueAutoscaler.apply_job_settings!

        # Uses the first configured worker's queue (converted to string)
        expect(described_class.queue_name).to eq('first_queue')
      end
    end

    describe 'Configuration#job_queue' do
      it 'defaults to :autoscaler' do
        config = SolidQueueAutoscaler::Configuration.new
        expect(config.job_queue).to eq(:autoscaler)
      end

      it 'can be set to a custom value' do
        config = SolidQueueAutoscaler::Configuration.new
        config.job_queue = :critical
        expect(config.job_queue).to eq(:critical)
      end
    end
  end

  describe 'job_priority configuration' do
    describe 'Configuration#job_priority defaults' do
      it 'defaults to nil' do
        config = SolidQueueAutoscaler::Configuration.new
        expect(config.job_priority).to be_nil
      end

      it 'can be set to an integer' do
        config = SolidQueueAutoscaler::Configuration.new
        config.job_priority = 0
        expect(config.job_priority).to eq(0)
      end
    end
  end

  describe '#perform' do
    let(:mock_result) do
      SolidQueueAutoscaler::Scaler::ScaleResult.new(
        success: true,
        decision: nil,
        metrics: nil,
        error: nil,
        skipped_reason: 'Autoscaler is disabled',
        executed_at: Time.current
      )
    end

    before do
      configure_autoscaler(enabled: false)
      allow(SolidQueueAutoscaler).to receive(:scale!).and_return(mock_result)
    end

    it 'calls scale! with the worker_name' do
      job = described_class.new
      job.perform(:default)

      expect(SolidQueueAutoscaler).to have_received(:scale!).with(:default)
    end

    it 'defaults to :default worker when no argument provided' do
      job = described_class.new
      job.perform

      expect(SolidQueueAutoscaler).to have_received(:scale!).with(:default)
    end
  end
end
