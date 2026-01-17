# frozen_string_literal: true

# Configure SolidQueueAutoscaler for testing
# This mirrors what a real Rails app would have

SolidQueueAutoscaler.configure(:worker) do |config|
  config.adapter = :heroku
  config.heroku_api_key = 'test-api-key'
  config.heroku_app_name = 'test-app'
  config.process_type = 'worker'
  config.job_queue = 'autoscaler'
  config.job_priority = 0
  config.min_workers = 1
  config.max_workers = 5
  config.enabled = false  # Don't actually scale in tests
  config.dry_run = true
end
