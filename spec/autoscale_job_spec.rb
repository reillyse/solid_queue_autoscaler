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
    describe 'class-level queue_name' do
      it 'has a static class-level queue_name of autoscaler' do
        # This ensures SolidQueue recurring jobs get the correct queue
        # when queue: is not specified in recurring.yml
        expect(described_class.queue_name).to eq('autoscaler')
      end

      it 'always uses autoscaler queue regardless of arguments' do
        job = described_class.new
        job.arguments = [:default]
        expect(job.queue_name.to_s).to eq('autoscaler')

        job.arguments = [:critical_worker]
        expect(job.queue_name.to_s).to eq('autoscaler')

        job.arguments = [:all]
        expect(job.queue_name.to_s).to eq('autoscaler')
      end
    end

    describe 'Configuration#job_queue' do
      # Note: job_queue config is kept for backwards compatibility but
      # AutoscaleJob now uses a static queue. Users should use set(queue:)
      # or recurring.yml queue: to override.

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
