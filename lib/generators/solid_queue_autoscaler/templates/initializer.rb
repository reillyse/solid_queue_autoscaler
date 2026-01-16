# frozen_string_literal: true

SolidQueueAutoscaler.configure do |config|
  # Required: Heroku settings
  # Generate an API key with: heroku authorizations:create -d "Solid Queue Autoscaler"
  config.heroku_api_key = ENV.fetch('HEROKU_API_KEY', nil)
  config.heroku_app_name = ENV.fetch('HEROKU_APP_NAME', nil)
  config.process_type = 'worker'

  # Worker limits
  config.min_workers = 1
  config.max_workers = 10

  # Scaling strategy:
  # :fixed - adds/removes fixed increment/decrement (default)
  # :proportional - calculates workers based on jobs/latency over threshold
  config.scaling_strategy = :fixed

  # Scale-up thresholds (trigger scale up when ANY threshold is exceeded)
  config.scale_up_queue_depth = 100      # Jobs waiting in queue
  config.scale_up_latency_seconds = 300  # Age of oldest job (5 minutes)
  config.scale_up_increment = 1          # Workers to add per scale event (fixed strategy)

  # Proportional scaling settings (when scaling_strategy is :proportional)
  # config.scale_up_jobs_per_worker = 50      # Add 1 worker per 50 jobs over threshold
  # config.scale_up_latency_per_worker = 60   # Add 1 worker per 60s over threshold
  # config.scale_down_jobs_per_worker = 50    # Remove 1 worker per 50 jobs under capacity

  # Scale-down thresholds (trigger scale down when ALL thresholds are met)
  config.scale_down_queue_depth = 10     # Jobs waiting in queue
  config.scale_down_latency_seconds = 30 # Age of oldest job
  config.scale_down_decrement = 1        # Workers to remove per scale event

  # Cooldowns (prevent rapid scaling)
  config.cooldown_seconds = 120 # Default cooldown for both directions
  # config.scale_up_cooldown_seconds = 60    # Override for scale up
  # config.scale_down_cooldown_seconds = 180 # Override for scale down

  # Safety settings
  config.dry_run = Rails.env.development? # Safe default for development
  config.enabled = Rails.env.production?  # Only enable in production

  # Cooldown persistence (survives dyno restarts)
  # Requires running: rails generate solid_queue_autoscaler:migration
  config.persist_cooldowns = true

  # Optional: Filter to specific queues (nil = all queues)
  # config.queues = ['default', 'mailers']

  # Optional: Custom logger
  # config.logger = Rails.logger

  # Dashboard & Event Recording
  # Record scale events to database for dashboard (requires dashboard migration)
  config.record_events = true
  # Also record no_change events (verbose, generates many records)
  # config.record_all_events = false
end
