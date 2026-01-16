# frozen_string_literal: true

# Load ActiveJob for testing AutoscaleJob
require 'active_job'
require 'active_job/test_helper'
require_relative '../lib/solid_queue_autoscaler/autoscale_job'

RSpec.describe SolidQueueAutoscaler::AutoscaleJob do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, error: nil) }

  before do
    allow_any_instance_of(described_class).to receive(:logger).and_return(logger)
    stub_const('Rails', double('Rails', logger: logger))
    SolidQueueAutoscaler.reset_configuration!
  end

  describe 'job_queue configuration' do
    describe 'Configuration#job_queue defaults' do
      it 'defaults to :autoscaler' do
        config = SolidQueueAutoscaler::Configuration.new
        expect(config.job_queue).to eq(:autoscaler)
      end

      it 'can be set to a custom value' do
        config = SolidQueueAutoscaler::Configuration.new
        config.job_queue = :critical
        expect(config.job_queue).to eq(:critical)
      end

      it 'can be set to a string' do
        config = SolidQueueAutoscaler::Configuration.new
        config.job_queue = 'high_priority'
        expect(config.job_queue).to eq('high_priority')
      end
    end

    describe 'queue_as behavior' do
      # Note: ActiveJob's queue_name returns strings, so we use .to_s for comparison

      context 'with default configuration' do
        before do
          configure_autoscaler(job_queue: :autoscaler)
        end

        it 'uses autoscaler queue by default' do
          job = described_class.new
          job.arguments = [:default]

          expect(job.queue_name.to_s).to eq('autoscaler')
        end

        it 'uses autoscaler when worker_name is nil' do
          job = described_class.new
          job.arguments = [nil]

          expect(job.queue_name.to_s).to eq('autoscaler')
        end

        it 'uses autoscaler when worker_name is :all' do
          job = described_class.new
          job.arguments = [:all]

          expect(job.queue_name.to_s).to eq('autoscaler')
        end

        it 'uses autoscaler when worker_name is "all" string' do
          job = described_class.new
          job.arguments = ['all']

          expect(job.queue_name.to_s).to eq('autoscaler')
        end
      end

      context 'with custom job_queue' do
        before do
          configure_autoscaler(job_queue: :critical)
        end

        it 'uses the configured queue' do
          job = described_class.new
          job.arguments = [:default]

          expect(job.queue_name.to_s).to eq('critical')
        end

        it 'uses the configured queue when worker_name is nil' do
          job = described_class.new
          job.arguments = [nil]

          expect(job.queue_name.to_s).to eq('critical')
        end

        it 'uses the configured queue when worker_name is :all' do
          job = described_class.new
          job.arguments = [:all]

          expect(job.queue_name.to_s).to eq('critical')
        end
      end

      context 'with multi-worker configurations' do
        before do
          SolidQueueAutoscaler.configure(:critical_worker) do |config|
            config.heroku_api_key = 'test-key'
            config.heroku_app_name = 'test-app'
            config.process_type = 'critical_worker'
            config.job_queue = :critical_autoscaler
          end

          SolidQueueAutoscaler.configure(:default_worker) do |config|
            config.heroku_api_key = 'test-key'
            config.heroku_app_name = 'test-app'
            config.process_type = 'worker'
            config.job_queue = :default_autoscaler
          end
        end

        it 'uses the queue from the specific worker configuration' do
          job = described_class.new
          job.arguments = [:critical_worker]

          expect(job.queue_name.to_s).to eq('critical_autoscaler')
        end

        it 'uses different queues for different workers' do
          critical_job = described_class.new
          critical_job.arguments = [:critical_worker]

          default_job = described_class.new
          default_job.arguments = [:default_worker]

          expect(critical_job.queue_name.to_s).to eq('critical_autoscaler')
          expect(default_job.queue_name.to_s).to eq('default_autoscaler')
        end

        it 'handles string worker names' do
          job = described_class.new
          job.arguments = ['critical_worker']

          expect(job.queue_name.to_s).to eq('critical_autoscaler')
        end

        it 'falls back to autoscaler for unconfigured worker names' do
          # Configure a third worker without specifying job_queue (uses default)
          SolidQueueAutoscaler.configure(:other_worker) do |config|
            config.heroku_api_key = 'test-key'
            config.heroku_app_name = 'test-app'
            config.process_type = 'other_worker'
            # job_queue not set, should use default :autoscaler
          end

          job = described_class.new
          job.arguments = [:other_worker]

          # Should use the default :autoscaler queue since job_queue wasn't set
          expect(job.queue_name.to_s).to eq('autoscaler')
        end
      end

      context 'when job_queue is nil' do
        before do
          configure_autoscaler(job_queue: nil)
        end

        it 'falls back to autoscaler' do
          job = described_class.new
          job.arguments = [:default]

          expect(job.queue_name.to_s).to eq('autoscaler')
        end
      end

      context 'edge cases for worker_name handling' do
        before do
          configure_autoscaler(job_queue: :test_queue)
        end

        it 'handles empty arguments array' do
          job = described_class.new
          job.arguments = []

          # When arguments is empty, arguments.first is nil
          expect(job.queue_name.to_s).to eq('test_queue')
        end

        it 'handles symbol worker names' do
          job = described_class.new
          job.arguments = [:default]

          expect(job.queue_name.to_s).to eq('test_queue')
        end

        it 'handles string worker names' do
          job = described_class.new
          job.arguments = ['default']

          expect(job.queue_name.to_s).to eq('test_queue')
        end
      end
    end

    describe 'integration with configure helper' do
      it 'sets job_queue through configure block' do
        SolidQueueAutoscaler.configure do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.job_queue = :high_priority
        end

        expect(SolidQueueAutoscaler.config.job_queue).to eq(:high_priority)
      end

      it 'sets job_queue through configure_autoscaler helper' do
        configure_autoscaler(job_queue: :fast)

        expect(SolidQueueAutoscaler.config.job_queue).to eq(:fast)
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

      it 'can be set to a higher priority value' do
        config = SolidQueueAutoscaler::Configuration.new
        config.job_priority = 10
        expect(config.job_priority).to eq(10)
      end
    end

    describe 'queue_with_priority behavior' do
      context 'with default configuration (nil priority)' do
        before do
          configure_autoscaler(job_priority: nil)
        end

        it 'returns nil priority by default' do
          job = described_class.new
          job.arguments = [:default]

          expect(job.priority).to be_nil
        end

        it 'returns nil when worker_name is nil' do
          job = described_class.new
          job.arguments = [nil]

          expect(job.priority).to be_nil
        end

        it 'returns nil when worker_name is :all' do
          job = described_class.new
          job.arguments = [:all]

          expect(job.priority).to be_nil
        end
      end

      context 'with custom job_priority' do
        before do
          configure_autoscaler(job_priority: 0)
        end

        it 'uses the configured priority' do
          job = described_class.new
          job.arguments = [:default]

          expect(job.priority).to eq(0)
        end

        it 'uses the configured priority when worker_name is nil' do
          job = described_class.new
          job.arguments = [nil]

          expect(job.priority).to eq(0)
        end

        it 'uses the configured priority when worker_name is :all' do
          job = described_class.new
          job.arguments = [:all]

          expect(job.priority).to eq(0)
        end
      end

      context 'with multi-worker configurations' do
        before do
          SolidQueueAutoscaler.configure(:critical_worker) do |config|
            config.heroku_api_key = 'test-key'
            config.heroku_app_name = 'test-app'
            config.process_type = 'critical_worker'
            config.job_priority = 0  # Highest priority
          end

          SolidQueueAutoscaler.configure(:default_worker) do |config|
            config.heroku_api_key = 'test-key'
            config.heroku_app_name = 'test-app'
            config.process_type = 'worker'
            config.job_priority = 10  # Lower priority
          end
        end

        it 'uses the priority from the specific worker configuration' do
          job = described_class.new
          job.arguments = [:critical_worker]

          expect(job.priority).to eq(0)
        end

        it 'uses different priorities for different workers' do
          critical_job = described_class.new
          critical_job.arguments = [:critical_worker]

          default_job = described_class.new
          default_job.arguments = [:default_worker]

          expect(critical_job.priority).to eq(0)
          expect(default_job.priority).to eq(10)
        end

        it 'handles string worker names' do
          job = described_class.new
          job.arguments = ['critical_worker']

          expect(job.priority).to eq(0)
        end

        it 'returns nil for workers without priority configured' do
          # Configure a third worker without specifying job_priority
          SolidQueueAutoscaler.configure(:other_worker) do |config|
            config.heroku_api_key = 'test-key'
            config.heroku_app_name = 'test-app'
            config.process_type = 'other_worker'
            # job_priority not set, should be nil
          end

          job = described_class.new
          job.arguments = [:other_worker]

          expect(job.priority).to be_nil
        end
      end

      context 'edge cases for priority values' do
        it 'handles zero priority (highest)' do
          configure_autoscaler(job_priority: 0)

          job = described_class.new
          job.arguments = [:default]

          expect(job.priority).to eq(0)
        end

        it 'handles negative priority' do
          configure_autoscaler(job_priority: -1)

          job = described_class.new
          job.arguments = [:default]

          expect(job.priority).to eq(-1)
        end

        it 'handles large priority values' do
          configure_autoscaler(job_priority: 1000)

          job = described_class.new
          job.arguments = [:default]

          expect(job.priority).to eq(1000)
        end
      end
    end

    describe 'integration with configure helper' do
      it 'sets job_priority through configure block' do
        SolidQueueAutoscaler.configure do |config|
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.job_priority = 5
        end

        expect(SolidQueueAutoscaler.config.job_priority).to eq(5)
      end

      it 'sets job_priority through configure_autoscaler helper' do
        configure_autoscaler(job_priority: 0)

        expect(SolidQueueAutoscaler.config.job_priority).to eq(0)
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
