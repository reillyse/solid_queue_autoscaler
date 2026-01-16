# frozen_string_literal: true

require 'active_record'
require 'active_support'
require 'active_support/core_ext/numeric/time'

require_relative 'solid_queue_autoscaler/version'
require_relative 'solid_queue_autoscaler/errors'
require_relative 'solid_queue_autoscaler/adapters'
require_relative 'solid_queue_autoscaler/configuration'
require_relative 'solid_queue_autoscaler/advisory_lock'
require_relative 'solid_queue_autoscaler/metrics'
require_relative 'solid_queue_autoscaler/decision_engine'
require_relative 'solid_queue_autoscaler/cooldown_tracker'
require_relative 'solid_queue_autoscaler/scale_event'
require_relative 'solid_queue_autoscaler/scaler'

module SolidQueueAutoscaler
  class << self
    # Registry of named configurations for multi-worker support
    def configurations
      @configurations ||= {}
    end

    # Configure a named worker type (default: :default for backward compatibility)
    # @param name [Symbol] The name of the worker type (e.g., :critical_worker, :default_worker)
    # @yield [Configuration] The configuration object to customize
    # @return [Configuration] The configured configuration object
    def configure(name = :default)
      config_obj = configurations[name] ||= Configuration.new
      config_obj.name = name
      yield(config_obj) if block_given?
      config_obj.validate!
      config_obj
    end

    # Get configuration for a named worker type
    # @param name [Symbol] The name of the worker type
    # @return [Configuration] The configuration object
    def config(name = :default)
      configurations[name] || configure(name)
    end

    # Scale a specific worker type
    # @param name [Symbol] The name of the worker type to scale
    # @return [Scaler::ScaleResult] The result of the scaling operation
    def scale!(name = :default)
      Scaler.new(config: config(name)).run
    end

    # Scale all configured worker types
    # @return [Hash<Symbol, Scaler::ScaleResult>] Results keyed by worker name
    def scale_all!
      return {} if configurations.empty?

      # Copy keys to avoid modifying hash during iteration
      worker_names = configurations.keys.dup
      worker_names.each_with_object({}) do |name, results|
        results[name] = scale!(name)
      end
    end

    # Get metrics for a specific worker type
    # @param name [Symbol] The name of the worker type
    # @return [Metrics::Result] The collected metrics
    def metrics(name = :default)
      Metrics.new(config: config(name)).collect
    end

    # Get current worker count for a specific worker type
    # @param name [Symbol] The name of the worker type
    # @return [Integer] The current number of workers
    def current_workers(name = :default)
      config(name).adapter.current_workers
    end

    # List all registered worker type names
    # @return [Array<Symbol>] List of configured worker names
    def registered_workers
      configurations.keys
    end

    # Reset all configurations (useful for testing)
    def reset_configuration!
      @configurations = {}
      Scaler.reset_cooldowns!
    end

    # Backward compatibility: single configuration accessor
    def configuration
      configurations[:default]
    end

    def configuration=(config_obj)
      if config_obj.nil?
        @configurations = {}
      else
        config_obj.name ||= :default
        configurations[:default] = config_obj
      end
    end
  end
end

require_relative 'solid_queue_autoscaler/railtie' if defined?(Rails::Railtie)
require_relative 'solid_queue_autoscaler/dashboard'

require_relative 'solid_queue_autoscaler/autoscale_job' if defined?(ActiveJob::Base)
