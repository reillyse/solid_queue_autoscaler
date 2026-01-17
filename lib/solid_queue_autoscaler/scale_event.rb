# frozen_string_literal: true

module SolidQueueAutoscaler
  # Lightweight model for recording autoscaler events.
  # Does not inherit from ActiveRecord to avoid requiring it as a dependency.
  # Uses raw SQL for compatibility with any database connection.
  class ScaleEvent
    TABLE_NAME = 'solid_queue_autoscaler_events'

    ACTIONS = %w[scale_up scale_down no_change skipped error].freeze

    attr_reader :id, :worker_name, :action, :from_workers, :to_workers,
                :reason, :queue_depth, :latency_seconds, :metrics_json,
                :dry_run, :created_at

    def initialize(attrs = {})
      @id = attrs[:id]
      @worker_name = attrs[:worker_name]
      @action = attrs[:action]
      @from_workers = attrs[:from_workers]
      @to_workers = attrs[:to_workers]
      @reason = attrs[:reason]
      @queue_depth = attrs[:queue_depth]
      @latency_seconds = attrs[:latency_seconds]
      @metrics_json = attrs[:metrics_json]
      @dry_run = attrs[:dry_run]
      @created_at = attrs[:created_at]
    end

    def scaled?
      %w[scale_up scale_down].include?(action)
    end

    def scale_up?
      action == 'scale_up'
    end

    def scale_down?
      action == 'scale_down'
    end

    def metrics
      return nil unless metrics_json

      JSON.parse(metrics_json, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    class << self
      # Diagnostic method to help debug why events aren't being saved.
      # @param config [Configuration, nil] Configuration to check (uses default if nil)
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter, nil] Database connection
      # @return [Hash] Diagnostic information
      def debug_event_saving(config: nil, connection: nil)
        config ||= SolidQueueAutoscaler.config rescue nil
        conn = connection || default_connection rescue nil

        diagnostics = {
          timestamp: Time.current,
          config_present: !config.nil?,
          connection_present: !conn.nil?,
          record_events_setting: nil,
          connection_available: false,
          record_events_effective: false,
          table_exists: false,
          can_query: false,
          can_insert: false,
          issues: [],
          connection_class: nil,
          error: nil
        }

        # Check config settings
        if config
          diagnostics[:record_events_setting] = config.record_events
          diagnostics[:connection_available] = config.connection_available?
          diagnostics[:record_events_effective] = config.record_events?

          unless config.record_events
            diagnostics[:issues] << 'config.record_events is false'
          end

          unless config.connection_available?
            diagnostics[:issues] << 'config.connection_available? returned false'
          end
        else
          diagnostics[:issues] << 'No configuration found'
        end

        # Check connection
        if conn
          diagnostics[:connection_class] = conn.class.name

          # Check table exists
          begin
            diagnostics[:table_exists] = conn.table_exists?(TABLE_NAME)
            unless diagnostics[:table_exists]
              diagnostics[:issues] << "Table '#{TABLE_NAME}' does not exist. Run: rails generate solid_queue_autoscaler:dashboard"
            end
          rescue StandardError => e
            diagnostics[:issues] << "Error checking table existence: #{e.message}"
          end

          # Check can query
          if diagnostics[:table_exists]
            begin
              conn.select_value("SELECT COUNT(*) FROM #{TABLE_NAME}")
              diagnostics[:can_query] = true
            rescue StandardError => e
              diagnostics[:issues] << "Error querying table: #{e.message}"
            end
          end

          # Check can insert (with rollback)
          if diagnostics[:can_query]
            begin
              # Try a test insert that we'll check but not actually commit
              test_sql = <<~SQL
                INSERT INTO #{TABLE_NAME}
                  (worker_name, action, from_workers, to_workers, reason,
                   queue_depth, latency_seconds, metrics_json, dry_run, created_at)
                VALUES
                  (#{conn.quote('_debug_test')},
                   #{conn.quote('skipped')},
                   #{conn.quote(0)},
                   #{conn.quote(0)},
                   #{conn.quote('debug test - should be deleted')},
                   #{conn.quote(0)},
                   #{conn.quote(0.0)},
                   #{conn.quote(nil)},
                   #{conn.quote(true)},
                   #{conn.quote(Time.current)})
                RETURNING id
              SQL

              result = conn.execute(test_sql)
              test_id = result.first&.fetch('id', nil)

              if test_id
                diagnostics[:can_insert] = true
                # Clean up test record
                conn.execute("DELETE FROM #{TABLE_NAME} WHERE id = #{test_id}")
              else
                diagnostics[:issues] << 'INSERT succeeded but no id returned'
              end
            rescue StandardError => e
              diagnostics[:issues] << "Error inserting test record: #{e.message}"
            end
          end
        else
          diagnostics[:issues] << 'No database connection available'
        end

        # Summary
        diagnostics[:would_save_events] = diagnostics[:record_events_effective] &&
                                          diagnostics[:table_exists] &&
                                          diagnostics[:can_insert]

        diagnostics
      rescue StandardError => e
        {
          timestamp: Time.current,
          error: "#{e.class}: #{e.message}",
          issues: ["Unexpected error during diagnostics: #{e.message}"]
        }
      end

      # Creates a new scale event record.
      # @param attrs [Hash] Event attributes
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Database connection
      # @return [ScaleEvent] The created event
      def create!(attrs, connection: nil)
        conn = connection || default_connection
        return nil unless table_exists?(conn)

        now = Time.current
        sql = <<~SQL
          INSERT INTO #{TABLE_NAME}
            (worker_name, action, from_workers, to_workers, reason,
             queue_depth, latency_seconds, metrics_json, dry_run, created_at)
          VALUES
            (#{conn.quote(attrs[:worker_name])},
             #{conn.quote(attrs[:action])},
             #{conn.quote(attrs[:from_workers])},
             #{conn.quote(attrs[:to_workers])},
             #{conn.quote(attrs[:reason])},
             #{conn.quote(attrs[:queue_depth])},
             #{conn.quote(attrs[:latency_seconds])},
             #{conn.quote(attrs[:metrics_json])},
             #{conn.quote(attrs[:dry_run])},
             #{conn.quote(now)})
          RETURNING id
        SQL

        result = conn.execute(sql)
        id = result.first&.fetch('id', nil)

        new(attrs.merge(id: id, created_at: now))
      rescue StandardError => e
        # Log but don't fail if event recording fails
        Rails.logger.warn("[Autoscaler] Failed to record event: #{e.message}") if defined?(Rails)
        nil
      end

      # Finds recent events.
      # @param limit [Integer] Maximum number of events to return
      # @param worker_name [String, nil] Filter by worker name
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Database connection
      # @return [Array<ScaleEvent>] Array of events
      def recent(limit: 50, worker_name: nil, connection: nil)
        conn = connection || default_connection
        return [] unless table_exists?(conn)

        filter = worker_name ? "WHERE worker_name = #{conn.quote(worker_name)}" : ''

        sql = <<~SQL
          SELECT id, worker_name, action, from_workers, to_workers, reason,
                 queue_depth, latency_seconds, metrics_json, dry_run, created_at
          FROM #{TABLE_NAME}
          #{filter}
          ORDER BY created_at DESC
          LIMIT #{limit.to_i}
        SQL

        conn.select_all(sql).map { |row| from_row(row) }
      rescue StandardError
        []
      end

      # Finds events by action type.
      # @param action [String] Action type (scale_up, scale_down, etc.)
      # @param limit [Integer] Maximum number of events
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Database connection
      # @return [Array<ScaleEvent>] Array of events
      def by_action(action, limit: 50, connection: nil)
        conn = connection || default_connection
        return [] unless table_exists?(conn)

        sql = <<~SQL
          SELECT id, worker_name, action, from_workers, to_workers, reason,
                 queue_depth, latency_seconds, metrics_json, dry_run, created_at
          FROM #{TABLE_NAME}
          WHERE action = #{conn.quote(action)}
          ORDER BY created_at DESC
          LIMIT #{limit.to_i}
        SQL

        conn.select_all(sql).map { |row| from_row(row) }
      rescue StandardError
        []
      end

      # Gets event statistics for a time period.
      # @param since [Time] Start time for statistics
      # @param worker_name [String, nil] Filter by worker name
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Database connection
      # @return [Hash] Statistics hash
      def stats(since: 24.hours.ago, worker_name: nil, connection: nil)
        conn = connection || default_connection
        return default_stats unless table_exists?(conn)

        worker_filter = worker_name ? "AND worker_name = #{conn.quote(worker_name)}" : ''

        sql = <<~SQL
          SELECT
            action,
            COUNT(*) as count,
            AVG(queue_depth) as avg_queue_depth,
            AVG(latency_seconds) as avg_latency
          FROM #{TABLE_NAME}
          WHERE created_at >= #{conn.quote(since)}
          #{worker_filter}
          GROUP BY action
        SQL

        results = conn.select_all(sql).to_a
        build_stats(results)
      rescue StandardError
        default_stats
      end

      # Cleans up old events.
      # @param keep_days [Integer] Number of days to keep
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Database connection
      # @return [Integer] Number of deleted records
      def cleanup!(keep_days: 30, connection: nil)
        conn = connection || default_connection
        return 0 unless table_exists?(conn)

        cutoff = Time.current - keep_days.days

        sql = <<~SQL
          DELETE FROM #{TABLE_NAME}
          WHERE created_at < #{conn.quote(cutoff)}
        SQL

        result = conn.execute(sql)
        result.cmd_tuples
      rescue StandardError
        0
      end

      # Checks if the events table exists.
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Database connection
      # @return [Boolean] True if table exists
      def table_exists?(connection = nil)
        conn = connection || default_connection
        conn.table_exists?(TABLE_NAME)
      rescue StandardError
        false
      end

      # Counts events in a time period.
      # @param since [Time] Start time
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Database connection
      # @return [Integer] Event count
      def count(since: nil, connection: nil)
        conn = connection || default_connection
        return 0 unless table_exists?(conn)

        time_filter = since ? "WHERE created_at >= #{conn.quote(since)}" : ''

        sql = "SELECT COUNT(*) FROM #{TABLE_NAME} #{time_filter}"
        conn.select_value(sql).to_i
      rescue StandardError
        0
      end

      # Returns diagnostic information to help debug event storage issues.
      # Use this method in Rails console to understand why events might not be stored.
      #
      # @example Check why events aren't being stored
      #   SolidQueueAutoscaler::ScaleEvent.diagnostics
      #   # => { table_exists: false, error: "Table does not exist..." }
      #
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Database connection
      # @return [Hash] Diagnostic information
      def diagnostics(connection: nil)
        conn = connection || default_connection
        result = {
          table_name: TABLE_NAME,
          connection_class: conn.class.name,
          table_exists: false,
          event_count: 0,
          recent_events: 0,
          last_event_at: nil,
          error: nil
        }

        # Check table existence
        begin
          result[:table_exists] = conn.table_exists?(TABLE_NAME)
        rescue StandardError => e
          result[:error] = "Failed to check table existence: #{e.message}"
          return result
        end

        unless result[:table_exists]
          result[:error] = "Table does not exist. Run: rails generate solid_queue_autoscaler:migration && rails db:migrate"
          return result
        end

        # Get event counts
        begin
          result[:event_count] = count(connection: conn)
          result[:recent_events] = count(since: 24.hours.ago, connection: conn)

          # Get last event time
          sql = "SELECT MAX(created_at) FROM #{TABLE_NAME}"
          last_at = conn.select_value(sql)
          result[:last_event_at] = last_at ? parse_time(last_at) : nil
        rescue StandardError => e
          result[:error] = "Failed to query events: #{e.message}"
        end

        # Add configuration info
        begin
          config = SolidQueueAutoscaler.config
          result[:config] = {
            record_events: config.record_events,
            record_all_events: config.record_all_events,
            record_events_effective: config.record_events?,
            connection_available: config.connection_available?
          }
        rescue StandardError => e
          result[:config_error] = e.message
        end

        result
      rescue StandardError => e
        { error: "Diagnostics failed: #{e.message}" }
      end

      private

      def default_connection
        # Use SolidQueue's connection for multi-database setups (same as Configuration.connection)
        if defined?(SolidQueue::Record) && SolidQueue::Record.respond_to?(:connection)
          return SolidQueue::Record.connection
        end

        ActiveRecord::Base.connection
      end

      def from_row(row)
        new(
          id: row['id'],
          worker_name: row['worker_name'],
          action: row['action'],
          from_workers: row['from_workers'].to_i,
          to_workers: row['to_workers'].to_i,
          reason: row['reason'],
          queue_depth: row['queue_depth'].to_i,
          latency_seconds: row['latency_seconds'].to_f,
          metrics_json: row['metrics_json'],
          dry_run: parse_boolean(row['dry_run']),
          created_at: parse_time(row['created_at'])
        )
      end

      def parse_boolean(value)
        case value
        when true, 't', 'true', '1', 1
          true
        else
          false
        end
      end

      def parse_time(value)
        case value
        when Time, DateTime
          value.to_time
        when String
          Time.parse(value)
        else
          value
        end
      end

      def default_stats
        {
          total: 0,
          scale_up_count: 0,
          scale_down_count: 0,
          no_change_count: 0,
          skipped_count: 0,
          error_count: 0,
          avg_queue_depth: 0,
          avg_latency: 0
        }
      end

      def build_stats(results)
        stats = default_stats

        results.each do |row|
          action = row['action']
          count = row['count'].to_i

          stats[:total] += count
          stats[:"#{action}_count"] = count

          # Use weighted average for overall metrics
          stats[:avg_queue_depth] += row['avg_queue_depth'].to_f * count if row['avg_queue_depth']
          stats[:avg_latency] += row['avg_latency'].to_f * count if row['avg_latency']
        end

        # Calculate averages
        if stats[:total].positive?
          stats[:avg_queue_depth] /= stats[:total]
          stats[:avg_latency] /= stats[:total]
        end

        stats
      end
    end
  end
end
