# frozen_string_literal: true

module SolidQueueHerokuAutoscaler
  class Railtie < Rails::Railtie
    initializer 'solid_queue_heroku_autoscaler.configure' do
      # Configuration happens via initializer, nothing to do here
    end

    rake_tasks do
      namespace :solid_queue_autoscaler do
        desc 'Run the autoscaler once for a specific worker (default: :default). Use WORKER=name'
        task scale: :environment do
          worker_name = (ENV['WORKER'] || 'default').to_sym
          result = SolidQueueHerokuAutoscaler.scale!(worker_name)
          print_scale_result(result, worker_name)
        end

        desc 'Run the autoscaler for all configured workers'
        task scale_all: :environment do
          results = SolidQueueHerokuAutoscaler.scale_all!
          if results.empty?
            puts 'No workers configured'
            exit 1
          end
          results.each do |worker_name, result|
            print_scale_result(result, worker_name)
          end
          exit 1 if results.values.any? { |r| !r.success? }
        end

        desc 'List all configured workers'
        task workers: :environment do
          workers = SolidQueueHerokuAutoscaler.registered_workers
          if workers.empty?
            puts 'No workers configured'
          else
            puts "Configured Workers (#{workers.size}):"
            workers.each do |name|
              config = SolidQueueHerokuAutoscaler.config(name)
              queues = config.queues&.join(', ') || 'all'
              puts "  #{name}:"
              puts "    Process Type: #{config.process_type}"
              puts "    Queues: #{queues}"
              puts "    Workers: #{config.min_workers}-#{config.max_workers}"
            end
          end
        end

        desc 'Show current queue metrics for a worker. Use WORKER=name'
        task metrics: :environment do
          worker_name = (ENV['WORKER'] || 'default').to_sym
          metrics = SolidQueueHerokuAutoscaler.metrics(worker_name)
          config = SolidQueueHerokuAutoscaler.config(worker_name)
          puts "Queue Metrics#{" [#{worker_name}]" unless worker_name == :default}:"
          puts "  Queues Filter: #{config.queues&.join(', ') || 'all'}"
          puts "  Queue Depth: #{metrics.queue_depth}"
          puts "  Oldest Job Age: #{metrics.oldest_job_age_seconds.round}s"
          puts "  Jobs/Minute: #{metrics.jobs_per_minute}"
          puts "  Claimed Jobs: #{metrics.claimed_jobs}"
          puts "  Failed Jobs: #{metrics.failed_jobs}"
          puts "  Blocked Jobs: #{metrics.blocked_jobs}"
          puts "  Active Workers: #{metrics.active_workers}"
          puts "  Queues Breakdown: #{metrics.queues_breakdown}"
        end

        desc 'Show current worker formation. Use WORKER=name'
        task formation: :environment do
          worker_name = (ENV['WORKER'] || 'default').to_sym
          workers = SolidQueueHerokuAutoscaler.current_workers(worker_name)
          config = SolidQueueHerokuAutoscaler.config(worker_name)
          puts "Current Formation#{" [#{worker_name}]" unless worker_name == :default}:"
          puts "  Process Type: #{config.process_type}"
          puts "  Workers: #{workers}"
          puts "  Min: #{config.min_workers}"
          puts "  Max: #{config.max_workers}"
          puts "  Queues: #{config.queues&.join(', ') || 'all'}"
        end

        desc 'Show cooldown state for a worker. Use WORKER=name'
        task cooldown: :environment do
          worker_name = (ENV['WORKER'] || 'default').to_sym
          config = SolidQueueHerokuAutoscaler.config(worker_name)
          tracker = SolidQueueHerokuAutoscaler::CooldownTracker.new(config: config, key: worker_name.to_s)

          puts "Cooldown State#{" [#{worker_name}]" unless worker_name == :default}:"
          puts "  Table Exists: #{tracker.table_exists?}"

          if tracker.table_exists?
            state = tracker.state
            puts "  Last Scale Up: #{state[:last_scale_up_at] || 'never'}"
            puts "  Last Scale Down: #{state[:last_scale_down_at] || 'never'}"
            puts "  Scale Up Cooldown Active: #{tracker.cooldown_active_for_scale_up?}"
            puts "  Scale Down Cooldown Active: #{tracker.cooldown_active_for_scale_down?}"

            if tracker.cooldown_active_for_scale_up?
              puts "  Scale Up Cooldown Remaining: #{tracker.scale_up_cooldown_remaining.round}s"
            end
            if tracker.cooldown_active_for_scale_down?
              puts "  Scale Down Cooldown Remaining: #{tracker.scale_down_cooldown_remaining.round}s"
            end
          else
            puts '  (Using in-memory cooldowns - run migration for persistence)'
            scale_up = SolidQueueHerokuAutoscaler::Scaler.last_scale_up_at(worker_name)
            scale_down = SolidQueueHerokuAutoscaler::Scaler.last_scale_down_at(worker_name)
            puts "  In-Memory Scale Up: #{scale_up || 'never'}"
            puts "  In-Memory Scale Down: #{scale_down || 'never'}"
          end
        end

        desc 'Reset cooldown state for a worker (or all if WORKER=all). Use WORKER=name'
        task reset_cooldown: :environment do
          worker_name = ENV['WORKER']&.to_sym

          if worker_name == :all || worker_name.nil?
            # Reset all workers
            SolidQueueHerokuAutoscaler.registered_workers.each do |name|
              config = SolidQueueHerokuAutoscaler.config(name)
              tracker = SolidQueueHerokuAutoscaler::CooldownTracker.new(config: config, key: name.to_s)
              tracker.reset! if tracker.table_exists?
            end
            SolidQueueHerokuAutoscaler::Scaler.reset_cooldowns!
            puts 'All cooldown states reset'
          else
            config = SolidQueueHerokuAutoscaler.config(worker_name)
            tracker = SolidQueueHerokuAutoscaler::CooldownTracker.new(config: config, key: worker_name.to_s)
            tracker.reset! if tracker.table_exists?
            SolidQueueHerokuAutoscaler::Scaler.reset_cooldowns!(worker_name)
            puts "Cooldown state reset for #{worker_name}"
          end
        end

        def print_scale_result(result, worker_name)
          prefix = worker_name == :default ? '' : "[#{worker_name}] "
          if result.success?
            if result.scaled?
              puts "#{prefix}Scaled #{result.decision.from} -> #{result.decision.to} workers"
            elsif result.skipped?
              puts "#{prefix}Skipped: #{result.skipped_reason}"
            else
              puts "#{prefix}No change needed: #{result.decision&.reason}"
            end
          else
            puts "#{prefix}Error: #{result.error}"
          end
        end
      end
    end
  end
end
