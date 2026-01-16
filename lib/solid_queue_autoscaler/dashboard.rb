# frozen_string_literal: true

require_relative 'dashboard/engine' if defined?(Rails::Engine)

module SolidQueueAutoscaler
  # Dashboard module provides a web UI for monitoring the autoscaler.
  # Integrates with Mission Control Solid Queue when available.
  module Dashboard
    class << self
      # Returns current autoscaler status for all workers
      # @return [Hash] Status information for all workers
      def status
        workers = SolidQueueAutoscaler.registered_workers
        workers = [:default] if workers.empty?

        workers.each_with_object({}) do |name, status|
          status[name] = worker_status(name)
        end
      end

      # Returns status for a specific worker
      # @param name [Symbol] Worker name
      # @return [Hash] Status information
      def worker_status(name)
        config = SolidQueueAutoscaler.config(name)
        metrics = safe_metrics(name)
        tracker = CooldownTracker.new(config: config, key: name.to_s)

        {
          name: name,
          enabled: config.enabled?,
          dry_run: config.dry_run?,
          current_workers: safe_current_workers(name),
          min_workers: config.min_workers,
          max_workers: config.max_workers,
          queues: config.queues || ['all'],
          process_type: config.process_type,
          scaling_strategy: config.scaling_strategy,
          metrics: {
            queue_depth: metrics&.queue_depth || 0,
            latency_seconds: metrics&.oldest_job_age_seconds || 0,
            jobs_per_minute: metrics&.jobs_per_minute || 0,
            claimed_jobs: metrics&.claimed_jobs || 0,
            failed_jobs: metrics&.failed_jobs || 0,
            active_workers: metrics&.active_workers || 0
          },
          cooldowns: {
            scale_up_remaining: tracker.scale_up_cooldown_remaining.round,
            scale_down_remaining: tracker.scale_down_cooldown_remaining.round,
            last_scale_up: tracker.last_scale_up_at,
            last_scale_down: tracker.last_scale_down_at
          },
          thresholds: {
            scale_up_queue_depth: config.scale_up_queue_depth,
            scale_up_latency: config.scale_up_latency_seconds,
            scale_down_queue_depth: config.scale_down_queue_depth,
            scale_down_latency: config.scale_down_latency_seconds
          }
        }
      end

      # Returns recent scale events
      # @param limit [Integer] Maximum events to return
      # @param worker_name [String, nil] Filter by worker
      # @return [Array<ScaleEvent>] Recent events
      def recent_events(limit: 50, worker_name: nil)
        ScaleEvent.recent(limit: limit, worker_name: worker_name)
      end

      # Returns event statistics
      # @param since [Time] Start time
      # @param worker_name [String, nil] Filter by worker
      # @return [Hash] Statistics
      def event_stats(since: 24.hours.ago, worker_name: nil)
        ScaleEvent.stats(since: since, worker_name: worker_name)
      end

      # Checks if the events table is available
      # @return [Boolean] True if events can be recorded
      def events_table_available?
        ScaleEvent.table_exists?
      end

      private

      def safe_metrics(name)
        SolidQueueAutoscaler.metrics(name)
      rescue StandardError
        nil
      end

      def safe_current_workers(name)
        SolidQueueAutoscaler.current_workers(name)
      rescue StandardError
        0
      end
    end
  end
end
