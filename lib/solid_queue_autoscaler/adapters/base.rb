# frozen_string_literal: true

module SolidQueueAutoscaler
  module Adapters
    # Base class for infrastructure platform adapters.
    #
    # Subclasses must implement:
    # - #current_workers - returns Integer count of current workers
    # - #scale(quantity) - scales to quantity workers, returns new count
    #
    # Subclasses may override:
    # - #name - human-readable adapter name (default: class name)
    # - #configured? - whether adapter has valid configuration (default: configuration_errors.empty?)
    # - #configuration_errors - array of configuration error messages (default: [])
    #
    # @example Creating a custom adapter
    #   class MyAdapter < SolidQueueAutoscaler::Adapters::Base
    #     def current_workers
    #       # Return current worker count
    #     end
    #
    #     def scale(quantity)
    #       return quantity if dry_run?
    #       # Scale to quantity workers
    #       quantity
    #     end
    #
    #     def configuration_errors
    #       errors = []
    #       errors << 'my_setting is required' if config.my_setting.nil?
    #       errors
    #     end
    #   end
    class Base
      # @param config [Configuration] the autoscaler configuration
      def initialize(config:)
        @config = config
      end

      # Returns the current number of workers.
      #
      # @return [Integer] current worker count
      # @raise [NotImplementedError] if not implemented by subclass
      def current_workers
        raise NotImplementedError, "#{self.class.name} must implement #current_workers"
      end

      # Scales to the specified number of workers.
      #
      # @param quantity [Integer] desired worker count
      # @return [Integer] the new worker count
      # @raise [NotImplementedError] if not implemented by subclass
      def scale(quantity)
        raise NotImplementedError, "#{self.class.name} must implement #scale(quantity)"
      end

      # Human-readable name of the adapter for logging.
      #
      # @return [String] adapter name
      def name
        self.class.name.split('::').last
      end

      # Checks if the adapter is properly configured.
      #
      # @return [Boolean] true if configured correctly
      def configured?
        configuration_errors.empty?
      end

      # Returns an array of configuration error messages.
      #
      # @return [Array<String>] error messages (empty if valid)
      def configuration_errors
        []
      end

      protected

      # @return [Configuration] the autoscaler configuration
      attr_reader :config

      # @return [Logger] the configured logger
      def logger
        config.logger
      end

      # @return [Boolean] true if dry-run mode is enabled
      def dry_run?
        config.dry_run?
      end

      # Logs a dry-run message at info level.
      #
      # @param message [String] the message to log
      # @return [void]
      def log_dry_run(message)
        logger.info("[DRY RUN] #{message}")
      end
    end
  end
end
