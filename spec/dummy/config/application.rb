require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

# Load our gem
require "solid_queue_autoscaler"

module Dummy
  class Application < Rails::Application
    config.load_defaults 8.1

    # Use SolidQueue as the ActiveJob queue adapter
    config.active_job.queue_adapter = :solid_queue

    # Don't generate system test files
    config.generators.system_tests = nil

    # Eager load for testing
    config.eager_load = false
  end
end
