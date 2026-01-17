# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.cache_store = :null_store
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false

  # Use SolidQueue for ActiveJob in tests
  config.active_job.queue_adapter = :solid_queue

  # Disable logging for cleaner test output
  config.log_level = :warn
end
