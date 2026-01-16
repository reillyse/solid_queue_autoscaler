# frozen_string_literal: true

module SolidQueueAutoscaler
  class DecisionEngine
    Decision = Struct.new(:action, :from, :to, :reason, keyword_init: true) do
      def scale_up?
        action == :scale_up
      end

      def scale_down?
        action == :scale_down
      end

      def no_change?
        action == :no_change
      end

      def delta
        to - from
      end
    end

    def initialize(config: nil)
      @config = config || SolidQueueAutoscaler.config
    end

    def decide(metrics:, current_workers:)
      return no_change_decision(current_workers, 'Autoscaler is disabled') unless @config.enabled?

      if should_scale_up?(metrics, current_workers)
        scale_up_decision(metrics, current_workers)
      elsif should_scale_down?(metrics, current_workers)
        scale_down_decision(metrics, current_workers)
      else
        no_change_decision(current_workers, determine_no_change_reason(metrics, current_workers))
      end
    end

    private

    def should_scale_up?(metrics, current_workers)
      return false if current_workers >= @config.max_workers

      queue_depth_high = metrics.queue_depth >= @config.scale_up_queue_depth
      latency_high = metrics.oldest_job_age_seconds >= @config.scale_up_latency_seconds

      queue_depth_high || latency_high
    end

    def should_scale_down?(metrics, current_workers)
      return false if current_workers <= @config.min_workers

      queue_depth_low = metrics.queue_depth <= @config.scale_down_queue_depth
      latency_low = metrics.oldest_job_age_seconds <= @config.scale_down_latency_seconds
      is_idle = metrics.idle?

      (queue_depth_low && latency_low) || is_idle
    end

    def scale_up_decision(metrics, current_workers)
      target = calculate_scale_up_target(metrics, current_workers)
      reason = build_scale_up_reason(metrics, current_workers, target)

      Decision.new(
        action: :scale_up,
        from: current_workers,
        to: target,
        reason: reason
      )
    end

    def scale_down_decision(metrics, current_workers)
      target = calculate_scale_down_target(metrics, current_workers)
      reason = build_scale_down_reason(metrics, current_workers, target)

      Decision.new(
        action: :scale_down,
        from: current_workers,
        to: target,
        reason: reason
      )
    end

    def calculate_scale_up_target(metrics, current_workers)
      raw_target = case @config.scaling_strategy
                   when :proportional
                     calculate_proportional_scale_up_target(metrics, current_workers)
                   when :step_function
                     calculate_step_function_target(metrics, current_workers)
                   else # :fixed
                     current_workers + @config.scale_up_increment
                   end

      [raw_target, @config.max_workers].min
    end

    def calculate_scale_down_target(metrics, current_workers)
      raw_target = case @config.scaling_strategy
                   when :proportional
                     calculate_proportional_scale_down_target(metrics, current_workers)
                   when :step_function
                     calculate_step_function_target(metrics, current_workers)
                   else # :fixed
                     current_workers - @config.scale_down_decrement
                   end

      [raw_target, @config.min_workers].max
    end

    def calculate_proportional_scale_up_target(metrics, current_workers)
      # Calculate workers needed based on queue depth
      jobs_over_threshold = [metrics.queue_depth - @config.scale_up_queue_depth, 0].max
      workers_for_depth = (jobs_over_threshold.to_f / @config.scale_up_jobs_per_worker).ceil

      # Calculate workers needed based on latency
      latency_over_threshold = [metrics.oldest_job_age_seconds - @config.scale_up_latency_seconds, 0].max
      workers_for_latency = (latency_over_threshold / @config.scale_up_latency_per_worker).ceil

      # Take the higher of the two calculations
      additional_workers = [workers_for_depth, workers_for_latency].max

      # Always add at least scale_up_increment if we're scaling up
      additional_workers = [@config.scale_up_increment, additional_workers].max

      current_workers + additional_workers
    end

    def calculate_proportional_scale_down_target(metrics, current_workers)
      # If idle, scale down aggressively
      return @config.min_workers if metrics.idle?

      # Calculate how much capacity we have based on queue depth
      jobs_under_capacity = [@config.scale_down_queue_depth - metrics.queue_depth, 0].max
      workers_to_remove = (jobs_under_capacity.to_f / @config.scale_down_jobs_per_worker).floor

      # Ensure we remove at least scale_down_decrement if we're scaling down
      workers_to_remove = [@config.scale_down_decrement, workers_to_remove].max

      current_workers - workers_to_remove
    end

    def calculate_step_function_target(metrics, current_workers)
      # Step function uses fixed thresholds (future implementation)
      # For now, fall back to fixed strategy
      if should_scale_up?(metrics, current_workers)
        current_workers + @config.scale_up_increment
      else
        current_workers - @config.scale_down_decrement
      end
    end

    def no_change_decision(current_workers, reason)
      Decision.new(
        action: :no_change,
        from: current_workers,
        to: current_workers,
        reason: reason
      )
    end

    def build_scale_up_reason(metrics, current_workers = nil, target = nil)
      reasons = []

      if metrics.queue_depth >= @config.scale_up_queue_depth
        reasons << "queue_depth=#{metrics.queue_depth} >= #{@config.scale_up_queue_depth}"
      end

      if metrics.oldest_job_age_seconds >= @config.scale_up_latency_seconds
        reasons << "latency=#{metrics.oldest_job_age_seconds.round}s >= #{@config.scale_up_latency_seconds}s"
      end

      base_reason = reasons.join(', ')

      if @config.scaling_strategy == :proportional && current_workers && target
        delta = target - current_workers
        "#{base_reason} [proportional: +#{delta} workers]"
      else
        base_reason
      end
    end

    def build_scale_down_reason(metrics, current_workers = nil, target = nil)
      if metrics.idle?
        base_reason = 'queue is idle (no pending or claimed jobs)'
      else
        reasons = []

        if metrics.queue_depth <= @config.scale_down_queue_depth
          reasons << "queue_depth=#{metrics.queue_depth} <= #{@config.scale_down_queue_depth}"
        end

        if metrics.oldest_job_age_seconds <= @config.scale_down_latency_seconds
          reasons << "latency=#{metrics.oldest_job_age_seconds.round}s <= #{@config.scale_down_latency_seconds}s"
        end

        base_reason = reasons.join(', ')
      end

      if @config.scaling_strategy == :proportional && current_workers && target
        delta = current_workers - target
        "#{base_reason} [proportional: -#{delta} workers]"
      else
        base_reason
      end
    end

    def determine_no_change_reason(metrics, current_workers)
      # Check if we would scale up but we're at max
      queue_depth_high = metrics.queue_depth >= @config.scale_up_queue_depth
      latency_high = metrics.oldest_job_age_seconds >= @config.scale_up_latency_seconds
      would_scale_up = queue_depth_high || latency_high

      # Check if we would scale down but we're at min
      queue_depth_low = metrics.queue_depth <= @config.scale_down_queue_depth
      latency_low = metrics.oldest_job_age_seconds <= @config.scale_down_latency_seconds
      is_idle = metrics.idle?
      would_scale_down = (queue_depth_low && latency_low) || is_idle

      if current_workers >= @config.max_workers && would_scale_up
        "at max_workers (#{@config.max_workers})"
      elsif current_workers <= @config.min_workers && would_scale_down
        "at min_workers (#{@config.min_workers})"
      else
        "metrics within normal range (depth=#{metrics.queue_depth}, latency=#{metrics.oldest_job_age_seconds.round}s)"
      end
    end
  end
end
