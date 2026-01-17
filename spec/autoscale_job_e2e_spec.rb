# frozen_string_literal: true

# End-to-end tests for AutoscaleJob queue configuration
# These tests verify the full enqueue path via perform_later,
# not just the queue_name property on job instances.

require 'active_job'
require 'active_job/test_helper'
require_relative '../lib/solid_queue_autoscaler/autoscale_job'

RSpec.describe SolidQueueAutoscaler::AutoscaleJob, 'e2e queue configuration' do
  include ActiveJob::TestHelper

  let(:logger) { instance_double(Logger, info: nil, debug: nil, error: nil) }

  before do
    # Use test adapter to capture enqueued jobs without actually performing them
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear

    allow_any_instance_of(described_class).to receive(:logger).and_return(logger)
    stub_const('Rails', double('Rails', logger: logger))
    SolidQueueAutoscaler.reset_configuration!
  end

  after do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
  end

  describe 'perform_later enqueues to autoscaler queue' do
    # AutoscaleJob uses a static queue_as :autoscaler to ensure compatibility
    # with SolidQueue recurring jobs. The queue is always 'autoscaler' unless
    # overridden with set(queue:) or in recurring.yml.

    context 'default behavior' do
      before do
        configure_autoscaler
      end

      it 'enqueues to autoscaler queue, NOT default' do
        described_class.perform_later(:default)

        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(enqueued[:queue]).to eq('autoscaler')
        expect(enqueued[:queue]).not_to eq('default')
      end

      it 'enqueues to autoscaler queue when no argument provided' do
        described_class.perform_later

        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(enqueued[:queue]).to eq('autoscaler')
        expect(enqueued[:queue]).not_to eq('default')
      end

      it 'enqueues to autoscaler queue with :all argument' do
        described_class.perform_later(:all)

        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(enqueued[:queue]).to eq('autoscaler')
        expect(enqueued[:queue]).not_to eq('default')
      end

      it 'enqueues to autoscaler queue with "all" string argument' do
        described_class.perform_later('all')

        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(enqueued[:queue]).to eq('autoscaler')
        expect(enqueued[:queue]).not_to eq('default')
      end
    end

    context 'with set(queue:) override' do
      before do
        configure_autoscaler
      end

      it 'allows overriding queue with set(queue:)' do
        described_class.set(queue: :my_custom_queue).perform_later(:default)

        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(enqueued[:queue]).to eq('my_custom_queue')
      end
    end

    context 'with multi-worker configurations' do
      before do
        SolidQueueAutoscaler.configure(:critical_worker) do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'critical_worker'
        end

        SolidQueueAutoscaler.configure(:default_worker) do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'worker'
        end
      end

      it 'enqueues all worker jobs to autoscaler queue by default' do
        described_class.perform_later(:critical_worker)
        described_class.perform_later(:default_worker)

        jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
        queues = jobs.map { |j| j[:queue] }

        expect(queues).to all(eq('autoscaler'))
        expect(queues).not_to include('default')
      end

      it 'can override queue per-job with set(queue:)' do
        described_class.set(queue: :critical_autoscaler).perform_later(:critical_worker)
        described_class.set(queue: :default_autoscaler).perform_later(:default_worker)

        jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
        queues = jobs.map { |j| j[:queue] }

        expect(queues).to include('critical_autoscaler')
        expect(queues).to include('default_autoscaler')
        expect(queues).not_to include('default')
      end
    end
  end

  describe 'IMPORTANT: SolidQueue recurring.yml queue setting' do
    # CRITICAL: AutoscaleJob uses a STATIC queue_as :autoscaler.
    # This ensures SolidQueue recurring jobs work correctly because:
    # 1. SolidQueue checks the job class's queue_name attribute
    # 2. A dynamic queue_as block returns a Proc that isn't evaluated
    # 3. With a static queue_as, queue_name returns 'autoscaler' directly
    #
    # Example recurring.yml configurations:
    #
    #   # Option 1: Omit queue: to use the class default ('autoscaler')
    #   autoscaler:
    #     class: SolidQueueAutoscaler::AutoscaleJob
    #     schedule: every 30 seconds
    #
    #   # Option 2: Explicitly set queue: (recommended for clarity)
    #   autoscaler:
    #     class: SolidQueueAutoscaler::AutoscaleJob
    #     queue: autoscaler
    #     schedule: every 30 seconds

    it 'has a static class-level queue_name of autoscaler for SolidQueue fallback' do
      # This verifies that the job class has a static default queue.
      # SolidQueue recurring jobs use this when queue: is not specified in recurring.yml.
      expect(described_class.queue_name).to eq('autoscaler'),
             "Expected class-level queue_name to be 'autoscaler', but got '#{described_class.queue_name}'"
    end

    it 'uses autoscaler queue by default with perform_later' do
      SolidQueueAutoscaler.configure do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
      end

      described_class.perform_later

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(enqueued[:queue]).to eq('autoscaler')
    end

    it 'allows set(queue:) to override the default queue' do
      SolidQueueAutoscaler.configure do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
      end

      # This is what happens when recurring.yml specifies a different queue
      described_class.set(queue: 'recurring_yaml_queue').perform_later

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(enqueued[:queue]).to eq('recurring_yaml_queue')
    end

    it 'uses autoscaler queue when set() is called without queue:' do
      SolidQueueAutoscaler.configure do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
      end

      # When set() is called without queue:, the static queue_as is used
      described_class.set(priority: 5).perform_later

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(enqueued[:queue]).to eq('autoscaler')
    end
  end

  describe 'regression: jobs should NEVER go to default queue' do
    # This is the specific regression test for the bug where jobs
    # were being enqueued to 'default' instead of 'autoscaler'.
    # AutoscaleJob now uses a static queue_as :autoscaler to ensure
    # SolidQueue recurring jobs work correctly.

    it 'REGRESSION: always enqueues to autoscaler, never default' do
      SolidQueueAutoscaler.configure do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
      end

      described_class.perform_later

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(enqueued[:queue]).to eq('autoscaler'),
             "Expected job to be enqueued to 'autoscaler' queue, but was enqueued to '#{enqueued[:queue]}'"
      expect(enqueued[:queue]).not_to eq('default'),
             "REGRESSION: Job was enqueued to 'default' queue!"
    end

    it 'REGRESSION: multi-worker jobs also go to autoscaler by default' do
      SolidQueueAutoscaler.configure(:special_worker) do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
        config.process_type = 'special'
      end

      described_class.perform_later(:special_worker)

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(enqueued[:queue]).to eq('autoscaler'),
             "Expected job to be enqueued to 'autoscaler', but was enqueued to '#{enqueued[:queue]}'"
      expect(enqueued[:queue]).not_to eq('default'),
             "REGRESSION: Job was enqueued to 'default' queue!"
    end

    it 'REGRESSION: can override queue with set(queue:) for custom needs' do
      SolidQueueAutoscaler.configure do |config|
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
      end

      # Users who need custom queues can use set(queue:)
      described_class.set(queue: :my_custom_queue).perform_later

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(enqueued[:queue]).to eq('my_custom_queue')
      expect(enqueued[:queue]).not_to eq('default')
    end
  end
end
