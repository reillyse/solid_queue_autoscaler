# frozen_string_literal: true

module SolidQueueHerokuAutoscaler
  class Scaler
    ScaleResult = Struct.new(
      :success,
      :decision,
      :metrics,
      :error,
      :skipped_reason,
      :executed_at,
      keyword_init: true
    ) do
      def success?
        success == true
      end

      def skipped?
        !skipped_reason.nil?
      end

      def scaled?
        success? && decision && !decision.no_change?
      end
    end

    # Per-configuration cooldown tracking for multi-worker support
    class << self
      def cooldown_mutex
        @cooldown_mutex ||= Mutex.new
      end

      def cooldowns
        @cooldowns ||= {}
      end

      def last_scale_up_at(config_name = :default)
        cooldown_mutex.synchronize { cooldowns.dig(config_name, :scale_up) }
      end

      def set_last_scale_up_at(config_name, value)
        cooldown_mutex.synchronize do
          cooldowns[config_name] ||= {}
          cooldowns[config_name][:scale_up] = value
        end
      end

      def last_scale_down_at(config_name = :default)
        cooldown_mutex.synchronize { cooldowns.dig(config_name, :scale_down) }
      end

      def set_last_scale_down_at(config_name, value)
        cooldown_mutex.synchronize do
          cooldowns[config_name] ||= {}
          cooldowns[config_name][:scale_down] = value
        end
      end

      def reset_cooldowns!(config_name = nil)
        cooldown_mutex.synchronize do
          if config_name
            cooldowns.delete(config_name)
          else
            @cooldowns = {}
          end
        end
      end

      # Backward compatibility setters
      def last_scale_up_at=(value)
        set_last_scale_up_at(:default, value)
      end

      def last_scale_down_at=(value)
        set_last_scale_down_at(:default, value)
      end
    end

    def initialize(config: nil)
      @config = config || SolidQueueHerokuAutoscaler.config
      @lock = AdvisoryLock.new(config: @config)
      @metrics_collector = Metrics.new(config: @config)
      @decision_engine = DecisionEngine.new(config: @config)
      @adapter = @config.adapter
    end

    def run
      return skipped_result('Autoscaler is disabled') unless @config.enabled?

      return skipped_result('Could not acquire advisory lock (another instance is running)') unless @lock.try_lock

      begin
        execute_scaling
      ensure
        @lock.release
      end
    end

    def run!
      @lock.with_lock do
        execute_scaling
      end
    end

    private

    def execute_scaling
      metrics = @metrics_collector.collect
      current_workers = @adapter.current_workers
      decision = @decision_engine.decide(metrics: metrics, current_workers: current_workers)

      log_decision(decision, metrics)

      return success_result(decision, metrics) if decision.no_change?

      if cooldown_active?(decision)
        remaining = cooldown_remaining(decision)
        return skipped_result("Cooldown active (#{remaining.round}s remaining)", decision: decision, metrics: metrics)
      end

      apply_decision(decision, metrics)
    rescue StandardError => e
      error_result(e)
    end

    def apply_decision(decision, metrics)
      @adapter.scale(decision.to)
      record_scale_time(decision)
      record_scale_event(decision, metrics)

      log_scale_action(decision)

      success_result(decision, metrics)
    end

    def cooldown_active?(decision)
      config_name = @config.name
      if decision.scale_up?
        last_scale_up = self.class.last_scale_up_at(config_name)
        return false unless last_scale_up

        Time.current - last_scale_up < @config.effective_scale_up_cooldown
      elsif decision.scale_down?
        last_scale_down = self.class.last_scale_down_at(config_name)
        return false unless last_scale_down

        Time.current - last_scale_down < @config.effective_scale_down_cooldown
      else
        false
      end
    end

    def cooldown_remaining(decision)
      config_name = @config.name
      if decision.scale_up?
        elapsed = Time.current - self.class.last_scale_up_at(config_name)
        @config.effective_scale_up_cooldown - elapsed
      else
        elapsed = Time.current - self.class.last_scale_down_at(config_name)
        @config.effective_scale_down_cooldown - elapsed
      end
    end

    def record_scale_time(decision)
      config_name = @config.name
      if decision.scale_up?
        self.class.set_last_scale_up_at(config_name, Time.current)
      elsif decision.scale_down?
        self.class.set_last_scale_down_at(config_name, Time.current)
      end
    end

    def log_decision(decision, metrics)
      worker_label = @config.name == :default ? '' : "[#{@config.name}] "
      logger.info(
        "[Autoscaler] #{worker_label}Evaluated: action=#{decision.action} " \
        "workers=#{decision.from}->#{decision.to} " \
        "queue_depth=#{metrics.queue_depth} " \
        "latency=#{metrics.oldest_job_age_seconds.round}s " \
        "reason=\"#{decision.reason}\""
      )
    end

    def log_scale_action(decision)
      prefix = @config.dry_run? ? '[DRY RUN] ' : ''
      worker_label = @config.name == :default ? '' : "[#{@config.name}] "
      logger.info(
        "#{prefix}[Autoscaler] #{worker_label}Scaling #{decision.action}: " \
        "#{decision.from} -> #{decision.to} workers (#{decision.reason})"
      )
    end

    def success_result(decision, metrics)
      # Record no_change events if configured
      record_scale_event(decision, metrics) if decision&.no_change? && @config.record_all_events?

      ScaleResult.new(
        success: true,
        decision: decision,
        metrics: metrics,
        executed_at: Time.current
      )
    end

    def skipped_result(reason, decision: nil, metrics: nil)
      logger.debug("[Autoscaler] Skipped: #{reason}")

      # Record skipped events
      record_skipped_event(reason, decision, metrics)

      ScaleResult.new(
        success: true,
        decision: decision,
        metrics: metrics,
        skipped_reason: reason,
        executed_at: Time.current
      )
    end

    def error_result(error)
      logger.error("[Autoscaler] Error: #{error.class}: #{error.message}")

      # Record error events
      record_error_event(error)

      ScaleResult.new(
        success: false,
        error: error,
        executed_at: Time.current
      )
    end

    def logger
      @config.logger
    end

    def record_scale_event(decision, metrics)
      return unless @config.record_events?

      ScaleEvent.create!(
        {
          worker_name: @config.name.to_s,
          action: decision.action.to_s,
          from_workers: decision.from,
          to_workers: decision.to,
          reason: decision.reason,
          queue_depth: metrics&.queue_depth || 0,
          latency_seconds: metrics&.oldest_job_age_seconds || 0.0,
          metrics_json: metrics&.to_h&.to_json,
          dry_run: @config.dry_run?
        },
        connection: @config.connection
      )
    end

    def record_skipped_event(reason, decision, metrics)
      return unless @config.record_events?

      ScaleEvent.create!(
        {
          worker_name: @config.name.to_s,
          action: 'skipped',
          from_workers: decision&.from || 0,
          to_workers: decision&.to || 0,
          reason: reason,
          queue_depth: metrics&.queue_depth || 0,
          latency_seconds: metrics&.oldest_job_age_seconds || 0.0,
          metrics_json: metrics&.to_h&.to_json,
          dry_run: @config.dry_run?
        },
        connection: @config.connection
      )
    end

    def record_error_event(error)
      return unless @config.record_events?

      ScaleEvent.create!(
        {
          worker_name: @config.name.to_s,
          action: 'error',
          from_workers: 0,
          to_workers: 0,
          reason: "#{error.class}: #{error.message}",
          queue_depth: 0,
          latency_seconds: 0.0,
          metrics_json: nil,
          dry_run: @config.dry_run?
        },
        connection: @config.connection
      )
    end
  end
end
