# frozen_string_literal: true

# SolidQueue Autoscaler Configuration for testing
# This tests the gem in a real Rails environment

SolidQueueAutoscaler.configure(:worker) do |config|
  config.adapter = :heroku
  config.heroku_api_key = ENV.fetch('HEROKU_API_KEY', 'test-api-key')
  config.heroku_app_name = ENV.fetch('HEROKU_APP_NAME', 'test-app')
  config.process_type = 'worker'
  config.min_workers = 1
  config.max_workers = 5
  config.job_queue = :autoscaler
  config.job_priority = 0
  config.dry_run = true
  config.enabled = true
end

SolidQueueAutoscaler.configure(:priority_worker) do |config|
  config.adapter = :heroku
  config.heroku_api_key = ENV.fetch('HEROKU_API_KEY', 'test-api-key')
  config.heroku_app_name = ENV.fetch('HEROKU_APP_NAME', 'test-app')
  config.process_type = 'priority_worker'
  config.min_workers = 1
  config.max_workers = 3
  config.job_queue = :autoscaler
  config.job_priority = 0
  config.dry_run = true
  config.enabled = true
end
