# frozen_string_literal: true

module SolidQueueAutoscaler
  class AutoscaleJob < ActiveJob::Base
    # IMPORTANT: Use a static queue name so SolidQueue recurring jobs work correctly.
    # When using SolidQueue recurring.yml without specifying queue:, SolidQueue
    # checks the job class's queue_name attribute. A dynamic queue_as block
    # returns a Proc that isn't evaluated by recurring jobs, causing jobs to
    # go to 'default' queue instead.
    #
    # To use a custom queue:
    # 1. Set queue: in your recurring.yml (recommended)
    # 2. Or use AutoscaleJob.set(queue: :my_queue).perform_later
    queue_as :autoscaler

    discard_on ConfigurationError

    # Scale a specific worker type, or all workers if :all is passed
    # @param worker_name [Symbol] The worker type to scale (:default, :critical_worker, etc.)
    #                             Pass :all to scale all registered workers
    def perform(worker_name = :default)
      if worker_name == :all
        perform_scale_all
      else
        perform_scale_one(worker_name)
      end
    end

    private

    def perform_scale_one(worker_name)
      result = SolidQueueAutoscaler.scale!(worker_name)

      if result.success?
        log_success(result, worker_name)
      else
        log_failure(result, worker_name)
        raise result.error if result.error
      end

      result
    end

    def perform_scale_all
      results = SolidQueueAutoscaler.scale_all!

      results.each do |worker_name, result|
        if result.success?
          log_success(result, worker_name)
        else
          log_failure(result, worker_name)
        end
      end

      # Raise the first error encountered, if any
      failed_result = results.values.find { |r| !r.success? && r.error }
      raise failed_result.error if failed_result

      results
    end

    def log_success(result, worker_name)
      worker_label = worker_name == :default ? '' : "[#{worker_name}] "
      if result.scaled?
        Rails.logger.info(
          "[AutoscaleJob] #{worker_label}Scaled workers: #{result.decision.from} -> #{result.decision.to} " \
          "(#{result.decision.reason})"
        )
      elsif result.skipped?
        Rails.logger.debug("[AutoscaleJob] #{worker_label}Skipped: #{result.skipped_reason}")
      else
        Rails.logger.debug("[AutoscaleJob] #{worker_label}No change: #{result.decision&.reason}")
      end
    end

    def log_failure(result, worker_name)
      worker_label = worker_name == :default ? '' : "[#{worker_name}] "
      Rails.logger.error("[AutoscaleJob] #{worker_label}Failed: #{result.error&.message}")
    end
  end
end
