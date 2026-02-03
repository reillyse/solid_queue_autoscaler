# frozen_string_literal: true

module SolidQueueAutoscaler
  class AutoscaleJob < ActiveJob::Base
    # Default queue - this MUST be set here (not dynamically) because SolidQueue
    # recurring jobs capture the queue name during initialization, BEFORE
    # Rails after_initialize hooks run.
    #
    # The apply_job_settings! method can override this after Rails initializers
    # run, but the default must be set here for SolidQueue recurring to work.
    #
    # You can customize the queue via:
    #   config.job_queue = :my_queue
    #
    # For SolidQueue recurring.yml, you can also set queue: directly in the YAML.
    queue_as :autoscaler

    discard_on ConfigurationError

    # Scale a specific worker type, or all workers if :all is passed
    # @param worker_name [Symbol] The worker type to scale (:default, :critical_worker, etc.)
    #                             Pass :all to scale all registered workers
    def perform(worker_name = :default)
      worker_name = normalize_worker_name(worker_name)

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

    # Normalize and validate worker_name argument.
    # Detects common YAML misconfiguration where symbols are quoted as strings.
    #
    # @param worker_name [Symbol, String] The worker name to normalize
    # @return [Symbol] The normalized worker name as a symbol
    # @raise [ConfigurationError] If a string that looks like a symbol is passed
    def normalize_worker_name(worker_name)
      return worker_name if worker_name.is_a?(Symbol)

      # Detect strings that look like symbols (e.g., ":all", ":default")
      # This is a common YAML misconfiguration
      if worker_name.is_a?(String) && worker_name.start_with?(':')
        symbol_name = worker_name[1..] # Remove the leading colon
        raise ConfigurationError,
              "Invalid worker_name argument: received string #{worker_name.inspect} instead of symbol :#{symbol_name}. " \
              "In your recurring.yml, change:\n" \
              "  args:\n" \
              "    - \"#{worker_name}\"\n" \
              "to:\n" \
              "  args:\n" \
              "    - :#{symbol_name}\n" \
              '(Remove the quotes around the symbol)'
      end

      # Convert plain strings to symbols (lenient mode)
      worker_name.to_sym
    end
  end
end
