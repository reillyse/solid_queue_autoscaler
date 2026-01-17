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

    # Verify the installation is complete and working.
    # Prints a human-friendly report (when verbose: true) and returns a VerificationResult.
    #
    # Usage (Rails/Heroku console):
    #   SolidQueueAutoscaler.verify_setup!
    #   # or alias:
    #   SolidQueueAutoscaler.verify_install!
    #
    # You can also inspect the returned struct:
    #   result = SolidQueueAutoscaler.verify_setup!(verbose: false)
    #   result.ok?   # => true/false
    #   result.to_h  # => hash of details
    def verify_setup!(name = :default, verbose: true)
      result = VerificationResult.new
      cfg = config(name)
      connection = cfg.connection

      output = []
      output << '=' * 60
      output << 'SolidQueueAutoscaler Setup Verification'
      output << '=' * 60
      output << ''
      output << "Version: #{VERSION}"
      output << "Configuration: #{name}"

      # Check connection type (handles SolidQueue in its own DB)
      if defined?(SolidQueue::Record) && SolidQueue::Record.respond_to?(:connection)
        output << '✓ Using SolidQueue::Record connection (multi-database setup)'
        result.connection_type = :solid_queue_record
      else
        output << '✓ Using ActiveRecord::Base connection'
        result.connection_type = :active_record_base
      end

      # 1. Cooldown state table
      output << ''
      output << '-' * 60
      output << '1. COOLDOWN STATE TABLE (solid_queue_autoscaler_state)'
      output << '-' * 60

      if connection.table_exists?(:solid_queue_autoscaler_state)
        result.state_table_exists = true
        output << '✓ Table exists'

        columns = connection.columns(:solid_queue_autoscaler_state).map(&:name)
        expected = %w[id key last_scale_up_at last_scale_down_at created_at updated_at]
        missing = expected - columns

        if missing.empty?
          result.state_table_columns_ok = true
          output << '  ✓ All expected columns present'
        else
          result.state_table_columns_ok = false
          result.add_warning("State table missing columns: #{missing.join(', ')}")
          output << "  ⚠ Missing columns: #{missing.join(', ')}"
        end

        state_count = connection.select_value('SELECT COUNT(*) FROM solid_queue_autoscaler_state').to_i
        output << "  Current records: #{state_count}"
      else
        result.state_table_exists = false
        result.add_error('Cooldown state table does not exist')
        output << '✗ Table DOES NOT EXIST'
        output << '  Run: rails generate solid_queue_autoscaler:migration && rails db:migrate'
        output << '  ⚠ Cooldowns are NOT shared across workers (using in-memory fallback)'
      end

      # 2. Events table
      output << ''
      output << '-' * 60
      output << '2. EVENTS TABLE (solid_queue_autoscaler_events)'
      output << '-' * 60

      if connection.table_exists?(:solid_queue_autoscaler_events)
        result.events_table_exists = true
        output << '✓ Table exists'

        columns = connection.columns(:solid_queue_autoscaler_events).map(&:name)
        expected = %w[id worker_name action from_workers to_workers reason queue_depth latency_seconds metrics_json dry_run created_at]
        missing = expected - columns

        if missing.empty?
          result.events_table_columns_ok = true
          output << '  ✓ All expected columns present'
        else
          result.events_table_columns_ok = false
          result.add_warning("Events table missing columns: #{missing.join(', ')}")
          output << "  ⚠ Missing columns: #{missing.join(', ')}"
        end

        event_count = connection.select_value('SELECT COUNT(*) FROM solid_queue_autoscaler_events').to_i
        output << "  Total events: #{event_count}"
      else
        result.events_table_exists = false
        result.add_error('Events table does not exist')
        output << '✗ Table DOES NOT EXIST'
        output << '  Run: rails generate solid_queue_autoscaler:migration && rails db:migrate'
        output << '  ⚠ Scale events are NOT being recorded (dashboard will be empty)'
      end

      # 3. Configuration
      output << ''
      output << '-' * 60
      output << '3. CONFIGURATION'
      output << '-' * 60

      begin
        result.config_valid = true
        output << '✓ Configuration loaded'
        output << "  enabled: #{cfg.enabled?}"
        output << "  dry_run: #{cfg.dry_run?}"
        output << "  persist_cooldowns: #{cfg.respond_to?(:persist_cooldowns) ? cfg.persist_cooldowns : '(not supported in this version)'}"
        output << "  record_events: #{cfg.respond_to?(:record_events) ? cfg.record_events : '(not supported in this version)'}"
        output << "  min_workers: #{cfg.min_workers}"
        output << "  max_workers: #{cfg.max_workers}"
        output << "  job_queue: #{cfg.job_queue}"
        output << "  adapter: #{cfg.adapter.class.name}"
      rescue StandardError => e
        result.config_valid = false
        result.add_error("Configuration error: #{e.message}")
        output << "✗ Configuration error: #{e.message}"
      end

      # 4. Adapter connectivity
      output << ''
      output << '-' * 60
      output << '4. ADAPTER CONNECTIVITY'
      output << '-' * 60

      begin
        workers = cfg.adapter.current_workers
        result.adapter_connected = true
        output << "✓ Adapter connected (current workers: #{workers})"
      rescue StandardError => e
        result.adapter_connected = false
        result.add_error("Adapter connection failed: #{e.message}")
        output << "✗ Adapter connection failed: #{e.message}"
      end

      # 5. Solid Queue tables
      output << ''
      output << '-' * 60
      output << '5. SOLID QUEUE TABLES'
      output << '-' * 60

      sq_tables = %w[solid_queue_jobs solid_queue_ready_executions solid_queue_claimed_executions solid_queue_processes]
      result.solid_queue_tables = {}

      sq_tables.each do |table|
        if connection.table_exists?(table)
          count = connection.select_value("SELECT COUNT(*) FROM #{table}").to_i
          result.solid_queue_tables[table] = count
          output << "✓ #{table}: #{count} records"
        else
          result.solid_queue_tables[table] = nil
          output << "✗ #{table}: MISSING"
        end
      end

      # Summary
      output << ''
      output << '=' * 60
      output << 'SUMMARY'
      output << '=' * 60

      if result.ok?
        output << '✓ All checks passed! Autoscaler is correctly configured.'
        if result.cooldowns_shared?
          output << '  Cooldowns: SHARED across workers (database-persisted)'
        else
          output << '  Cooldowns: In-memory only (not shared across workers)'
        end
        if result.events_table_exists
          output << '  Events: RECORDING to database'
        else
          output << '  Events: NOT recording (events table missing)'
        end
      else
        output << '⚠ Some issues found:'
        result.errors.each { |err| output << "  ✗ #{err}" }
        result.warnings.each { |warn| output << "  ⚠ #{warn}" }
        output << ''
        output << 'To fix missing tables, run:'
        output << '  rails generate solid_queue_autoscaler:migration'
        output << '  rails db:migrate'
      end

      puts output.join("\n") if verbose

      nil
    end

    # Convenience alias so users can call verify_install! as requested
    def verify_install!(name = :default, verbose: true)
      verify_setup!(name, verbose: verbose)
    end
  end

  # Structured result from verify_setup!/verify_install!
  class VerificationResult
    attr_accessor :connection_type,
                  :state_table_exists, :state_table_columns_ok,
                  :events_table_exists, :events_table_columns_ok,
                  :config_valid, :adapter_connected,
                  :solid_queue_tables

    def initialize
      @errors = []
      @warnings = []
      @solid_queue_tables = {}
    end

    def errors
      @errors
    end

    def warnings
      @warnings
    end

    def add_error(message)
      @errors << message
    end

    def add_warning(message)
      @warnings << message
    end

    def ok?
      @errors.empty?
    end

    def tables_exist?
      state_table_exists && events_table_exists
    end

    def cooldowns_shared?
      state_table_exists && state_table_columns_ok
    end

    def to_h
      {
        ok: ok?,
        connection_type: connection_type,
        state_table: { exists: state_table_exists, columns_ok: state_table_columns_ok },
        events_table: { exists: events_table_exists, columns_ok: events_table_columns_ok },
        config_valid: config_valid,
        adapter_connected: adapter_connected,
        solid_queue_tables: solid_queue_tables,
        errors: errors,
        warnings: warnings
      }
    end
  end
end

require_relative 'solid_queue_autoscaler/railtie' if defined?(Rails::Railtie)
require_relative 'solid_queue_autoscaler/dashboard'

require_relative 'solid_queue_autoscaler/autoscale_job' if defined?(ActiveJob::Base)
