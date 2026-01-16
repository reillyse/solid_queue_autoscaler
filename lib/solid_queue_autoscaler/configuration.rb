# frozen_string_literal: true

require 'logger'

module SolidQueueAutoscaler
  class Configuration
    # Configuration name (for multi-worker support)
    attr_accessor :name

    # Heroku settings
    attr_accessor :heroku_api_key

    # Worker limits
    attr_accessor :min_workers

    # Scale-up thresholds
    attr_accessor :scale_up_queue_depth

    # Scale-down thresholds
    attr_accessor :scale_down_queue_depth

    # Scaling strategy
    attr_accessor :scaling_strategy

    # Safety settings
    attr_accessor :cooldown_seconds

    # Advisory lock settings
    attr_accessor :lock_timeout_seconds

    # Behavior settings
    attr_accessor :dry_run

    # Queue filtering
    attr_accessor :queues

    # Database connection
    attr_accessor :database_connection

    # Solid Queue table prefix (default: 'solid_queue_')
    attr_accessor :table_prefix

    # Infrastructure adapter (defaults to Heroku)
    attr_accessor :adapter_class

    # Kubernetes settings (for Kubernetes adapter)
    attr_accessor :kubernetes_deployment, :kubernetes_namespace, :kubernetes_context, :kubernetes_kubeconfig

    # Additional Heroku settings
    attr_accessor :heroku_app_name, :process_type, :max_workers

    # Scale-up settings
    attr_accessor :scale_up_latency_seconds, :scale_up_increment

    # Scale-down settings
    attr_accessor :scale_down_latency_seconds, :scale_down_idle_minutes, :scale_down_decrement
    attr_accessor :scale_up_jobs_per_worker, :scale_up_latency_per_worker, :scale_up_cooldown_seconds, :scale_down_jobs_per_worker, :scale_down_cooldown_seconds

    # Other settings
    attr_accessor :enabled, :logger
    attr_writer :lock_key

    # Dashboard/event recording settings
    attr_accessor :record_events, :record_all_events

    def initialize
      # Configuration name (auto-set when using named configurations)
      @name = :default

      # Heroku settings - required
      @heroku_api_key = ENV.fetch('HEROKU_API_KEY', nil)
      @heroku_app_name = ENV.fetch('HEROKU_APP_NAME', nil)
      @process_type = 'worker'

      # Worker limits
      @min_workers = 1
      @max_workers = 10

      # Scale-up thresholds
      @scale_up_queue_depth = 100
      @scale_up_latency_seconds = 300
      @scale_up_increment = 1

      # Scale-down thresholds
      @scale_down_queue_depth = 10
      @scale_down_latency_seconds = 30
      @scale_down_idle_minutes = 5
      @scale_down_decrement = 1

      # Scaling strategy (:fixed or :proportional)
      @scaling_strategy = :fixed
      @scale_up_jobs_per_worker = 50
      @scale_up_latency_per_worker = 60
      @scale_down_jobs_per_worker = 50

      # Safety settings
      @cooldown_seconds = 120
      @scale_up_cooldown_seconds = nil
      @scale_down_cooldown_seconds = nil

      # Advisory lock settings
      @lock_timeout_seconds = 30
      @lock_key = nil # Auto-generated based on name if not set

      # Behavior
      @dry_run = false
      @enabled = true
      @logger = default_logger

      # Queue filtering (nil = all queues)
      @queues = nil

      # Database connection (defaults to ActiveRecord::Base.connection)
      @database_connection = nil

      # Solid Queue table prefix (default: 'solid_queue_')
      @table_prefix = 'solid_queue_'

      # Infrastructure adapter (defaults to Heroku)
      @adapter_class = nil

      # Kubernetes settings (for Kubernetes adapter)
      @kubernetes_deployment = ENV.fetch('K8S_DEPLOYMENT', nil)
      @kubernetes_namespace = ENV['K8S_NAMESPACE'] || 'default'
      @kubernetes_context = ENV.fetch('K8S_CONTEXT', nil)
      @kubernetes_kubeconfig = ENV.fetch('KUBECONFIG', nil)

      # Dashboard/event recording settings
      @record_events = true # Record scale events to database
      @record_all_events = false # Also record no_change events (verbose)
    end

    # Returns the lock key, auto-generating based on name if not explicitly set
    # Each worker type gets a unique lock to allow parallel scaling
    def lock_key
      @lock_key || "solid_queue_autoscaler_#{name}"
    end

    VALID_SCALING_STRATEGIES = %i[fixed proportional].freeze

    def validate!
      errors = []

      # Validate adapter-specific configuration
      errors.concat(adapter.configuration_errors)

      errors << 'min_workers must be >= 0' if min_workers.negative?
      errors << 'max_workers must be > 0' if max_workers <= 0
      errors << 'min_workers cannot exceed max_workers' if min_workers > max_workers

      errors << 'scale_up_queue_depth must be > 0' if scale_up_queue_depth <= 0
      errors << 'scale_up_latency_seconds must be > 0' if scale_up_latency_seconds <= 0
      errors << 'scale_up_increment must be > 0' if scale_up_increment <= 0

      errors << 'scale_down_queue_depth must be >= 0' if scale_down_queue_depth.negative?
      errors << 'scale_down_decrement must be > 0' if scale_down_decrement <= 0

      errors << 'cooldown_seconds must be >= 0' if cooldown_seconds.negative?
      errors << 'lock_timeout_seconds must be > 0' if lock_timeout_seconds <= 0

      if table_prefix.nil? || table_prefix.to_s.strip.empty?
        errors << 'table_prefix cannot be nil or empty'
      elsif !table_prefix.to_s.end_with?('_')
        errors << 'table_prefix must end with an underscore'
      end

      unless VALID_SCALING_STRATEGIES.include?(scaling_strategy)
        errors << "scaling_strategy must be one of: #{VALID_SCALING_STRATEGIES.join(', ')}"
      end

      raise ConfigurationError, errors.join(', ') if errors.any?

      true
    end

    def effective_scale_up_cooldown
      scale_up_cooldown_seconds || cooldown_seconds
    end

    def effective_scale_down_cooldown
      scale_down_cooldown_seconds || cooldown_seconds
    end

    def connection
      database_connection || ActiveRecord::Base.connection
    end

    def dry_run?
      dry_run
    end

    def enabled?
      enabled
    end

    def record_events?
      record_events && connection_available?
    end

    def record_all_events?
      record_all_events && record_events?
    end

    def connection_available?
      return true if database_connection
      return false unless defined?(ActiveRecord::Base)

      ActiveRecord::Base.connected?
    rescue StandardError
      false
    end

    # Returns the configured adapter instance.
    # Creates a new instance from adapter_class if not set.
    # Defaults to Heroku adapter.
    def adapter
      @adapter ||= begin
        klass = adapter_class || Adapters::Heroku
        klass.new(config: self)
      end
    end

    # Allow setting a pre-configured adapter instance or a symbol shortcut
    # @param value [Symbol, Base, Class] :heroku, :kubernetes, an adapter instance, or adapter class
    def adapter=(value)
      @adapter = case value
                 when Symbol
                   resolve_adapter_symbol(value)
                 when Class
                   value.new(config: self)
                 else
                   value
                 end
    end

    # Maps adapter symbols to adapter classes
    ADAPTER_SYMBOLS = {
      heroku: 'SolidQueueAutoscaler::Adapters::Heroku',
      kubernetes: 'SolidQueueAutoscaler::Adapters::Kubernetes',
      k8s: 'SolidQueueAutoscaler::Adapters::Kubernetes'
    }.freeze

    private

    def resolve_adapter_symbol(symbol)
      class_name = ADAPTER_SYMBOLS[symbol]
      unless class_name
        raise ConfigurationError,
              "Unknown adapter: #{symbol}. Valid options: #{ADAPTER_SYMBOLS.keys.join(', ')}"
      end

      klass = class_name.split('::').reduce(Object) { |mod, name| mod.const_get(name) }
      klass.new(config: self)
    end

    def default_logger
      if defined?(Rails) && Rails.logger
        Rails.logger
      else
        Logger.new($stdout).tap do |logger|
          logger.level = Logger::INFO
          logger.formatter = proc do |severity, datetime, _progname, msg|
            "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] [SolidQueueAutoscaler] #{severity}: #{msg}\n"
          end
        end
      end
    end
  end
end
