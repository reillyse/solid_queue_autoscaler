# frozen_string_literal: true

module SolidQueueAutoscaler
  class AutoscaleJob < ActiveJob::Base
    # Use configured queue for the target worker (defaults to :autoscaler)
    queue_as do
      # perform(worker_name = :default)
      worker_name = arguments.first

      # When scaling all workers, or when worker_name is nil, use the default configuration
      config_name =
        if worker_name.nil? || worker_name == :all || worker_name == "all"
          :default
        else
          # Handle both Symbol and String values safely
          worker_name.to_sym rescue :default
        end

      SolidQueueAutoscaler.config(config_name).job_queue || :autoscaler
    end

    # Use configured priority for the target worker (defaults to nil/no priority)
    queue_with_priority do
      # perform(worker_name = :default)
      worker_name = arguments.first

      # When scaling all workers, or when worker_name is nil, use the default configuration
      config_name =
        if worker_name.nil? || worker_name == :all || worker_name == "all"
          :default
        else
          # Handle both Symbol and String values safely
          worker_name.to_sym rescue :default
        end

      SolidQueueAutoscaler.config(config_name).job_priority
    end

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
