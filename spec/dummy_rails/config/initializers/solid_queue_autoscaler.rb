# frozen_string_literal: true

# SolidQueue Autoscaler Configuration for testing
# This tests the gem in a real Rails environment
# ALL configuration options are explicitly set for comprehensive testing

SolidQueueAutoscaler.configure(:worker) do |config|
  # Adapter configuration
  config.adapter = :heroku
  config.heroku_api_key = ENV.fetch('HEROKU_API_KEY', 'test-api-key')
  config.heroku_app_name = ENV.fetch('HEROKU_APP_NAME', 'test-app')
  config.process_type = 'worker'

  # Worker limits
  config.min_workers = 1
  config.max_workers = 5

  # Job settings
  config.job_queue = :autoscaler
  config.job_priority = 10

  # Scaling strategy
  config.scaling_strategy = :fixed
  config.scale_up_increment = 2
  config.scale_down_decrement = 1

  # Scale-up thresholds
  config.scale_up_queue_depth = 100
  config.scale_up_latency_seconds = 300

  # Scale-down thresholds
  config.scale_down_queue_depth = 10
  config.scale_down_latency_seconds = 30

  # Cooldown settings
  config.cooldown_seconds = 120
  config.scale_up_cooldown_seconds = 60
  config.scale_down_cooldown_seconds = 180

  # Queue filtering (nil = all queues)
  config.queues = nil

  # Behavior flags
  config.dry_run = true
  config.enabled = true

  # Event recording
  config.record_events = true
  config.record_all_events = false

  # Cooldown persistence
  config.persist_cooldowns = true

  # Table and lock settings
  config.table_prefix = 'solid_queue_'
  config.lock_key = 'autoscaler_worker_lock'
  config.lock_timeout_seconds = 30
end

SolidQueueAutoscaler.configure(:priority_worker) do |config|
  # Adapter configuration
  config.adapter = :heroku
  config.heroku_api_key = ENV.fetch('HEROKU_API_KEY', 'test-api-key')
  config.heroku_app_name = ENV.fetch('HEROKU_APP_NAME', 'test-app')
  config.process_type = 'priority_worker'

  # Worker limits
  config.min_workers = 1
  config.max_workers = 3

  # Job settings
  config.job_queue = :autoscaler
  config.job_priority = 5

  # Scaling strategy - use proportional for variety
  config.scaling_strategy = :proportional
  config.scale_up_jobs_per_worker = 50
  config.scale_up_latency_per_worker = 60
  config.scale_down_jobs_per_worker = 25

  # Scale-up thresholds
  config.scale_up_queue_depth = 50
  config.scale_up_latency_seconds = 120

  # Scale-down thresholds
  config.scale_down_queue_depth = 5
  config.scale_down_latency_seconds = 15

  # Cooldown settings
  config.cooldown_seconds = 60

  # Queue filtering - monitor specific queues
  config.queues = %w[indexing mailers notifications]

  # Behavior flags
  config.dry_run = true
  config.enabled = true

  # Event recording
  config.record_events = true
  config.record_all_events = true

  # Cooldown persistence
  config.persist_cooldowns = false

  # Table and lock settings
  config.table_prefix = 'solid_queue_'
  config.lock_key = 'autoscaler_priority_lock'
  config.lock_timeout_seconds = 45
end
