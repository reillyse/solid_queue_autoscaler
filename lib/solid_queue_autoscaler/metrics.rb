# frozen_string_literal: true

module SolidQueueAutoscaler
  class Metrics
    Result = Struct.new(
      :queue_depth,
      :oldest_job_age_seconds,
      :jobs_per_minute,
      :claimed_jobs,
      :failed_jobs,
      :blocked_jobs,
      :active_workers,
      :queues_breakdown,
      :collected_at,
      keyword_init: true
    ) do
      def idle?
        queue_depth.zero? && claimed_jobs.zero?
      end

      def latency_seconds
        oldest_job_age_seconds
      end

      def to_h
        {
          queue_depth: queue_depth,
          oldest_job_age_seconds: oldest_job_age_seconds,
          jobs_per_minute: jobs_per_minute,
          claimed_jobs: claimed_jobs,
          failed_jobs: failed_jobs,
          blocked_jobs: blocked_jobs,
          active_workers: active_workers,
          queues_breakdown: queues_breakdown,
          collected_at: collected_at
        }
      end
    end

    def initialize(config: nil)
      @config = config || SolidQueueAutoscaler.config
    end

    def collect
      Result.new(
        queue_depth: queue_depth,
        oldest_job_age_seconds: oldest_job_age_seconds,
        jobs_per_minute: jobs_per_minute,
        claimed_jobs: claimed_jobs_count,
        failed_jobs: failed_jobs_count,
        blocked_jobs: blocked_jobs_count,
        active_workers: active_workers_count,
        queues_breakdown: queues_breakdown,
        collected_at: Time.current
      )
    end

    def queue_depth
      sql = <<~SQL
        SELECT COUNT(*) FROM #{ready_executions_table}
        WHERE 1=1
        #{queue_filter_clause}
      SQL
      connection.select_value(sql).to_i
    end

    def oldest_job_age_seconds
      sql = <<~SQL
        SELECT EXTRACT(EPOCH FROM (NOW() - MIN(created_at)))
        FROM #{ready_executions_table}
        WHERE 1=1
        #{queue_filter_clause}
      SQL
      result = connection.select_value(sql)
      result.to_f
    end

    def jobs_per_minute
      sql = <<~SQL
        SELECT COUNT(*)
        FROM #{jobs_table}
        WHERE finished_at IS NOT NULL
          AND finished_at > NOW() - INTERVAL '1 minute'
          #{queue_filter_clause('queue_name')}
      SQL
      connection.select_value(sql).to_i
    end

    def claimed_jobs_count
      sql = <<~SQL
        SELECT COUNT(*) FROM #{claimed_executions_table}
      SQL
      connection.select_value(sql).to_i
    end

    def failed_jobs_count
      sql = <<~SQL
        SELECT COUNT(*) FROM #{failed_executions_table}
      SQL
      connection.select_value(sql).to_i
    end

    def blocked_jobs_count
      sql = <<~SQL
        SELECT COUNT(*) FROM #{blocked_executions_table}
      SQL
      connection.select_value(sql).to_i
    end

    def active_workers_count
      sql = <<~SQL
        SELECT COUNT(*)
        FROM #{processes_table}
        WHERE kind = 'Worker'
          AND last_heartbeat_at > NOW() - INTERVAL '5 minutes'
      SQL
      connection.select_value(sql).to_i
    end

    def queues_breakdown
      sql = <<~SQL
        SELECT queue_name, COUNT(*) as count
        FROM #{ready_executions_table}
        GROUP BY queue_name
        ORDER BY count DESC
      SQL
      connection.select_all(sql).to_a.to_h { |row| [row['queue_name'], row['count'].to_i] }
    end

    private

    def connection
      @config.connection
    end

    def queue_filter_clause(column_name = 'queue_name')
      return '' unless @config.queues&.any?

      quoted_queues = @config.queues.map { |q| connection.quote(q) }.join(', ')
      "AND #{column_name} IN (#{quoted_queues})"
    end

    # Table name helpers using configurable prefix
    def table_prefix
      @config.table_prefix
    end

    def ready_executions_table
      "#{table_prefix}ready_executions"
    end

    def jobs_table
      "#{table_prefix}jobs"
    end

    def claimed_executions_table
      "#{table_prefix}claimed_executions"
    end

    def failed_executions_table
      "#{table_prefix}failed_executions"
    end

    def blocked_executions_table
      "#{table_prefix}blocked_executions"
    end

    def processes_table
      "#{table_prefix}processes"
    end
  end
end
