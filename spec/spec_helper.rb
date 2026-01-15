# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_group 'Adapters', 'lib/solid_queue_heroku_autoscaler/adapters'
  add_group 'Core', 'lib/solid_queue_heroku_autoscaler'

  # Set minimum coverage threshold (optional - uncomment to enforce)
  # minimum_coverage 90

  enable_coverage :branch
end

require 'bundler/setup'
require 'solid_queue_heroku_autoscaler'
require 'webmock/rspec'

# Disable all external HTTP connections by default
WebMock.disable_net_connect!

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed

  config.before(:each) do
    SolidQueueHerokuAutoscaler.reset_configuration!
    SolidQueueHerokuAutoscaler::Scaler.reset_cooldowns!
  end
end

# Test helper to configure with valid defaults
def configure_autoscaler(overrides = {})
  SolidQueueHerokuAutoscaler.configure do |config|
    config.heroku_api_key = overrides[:heroku_api_key] || 'test-api-key'
    config.heroku_app_name = overrides[:heroku_app_name] || 'test-app'
    config.process_type = overrides[:process_type] || 'worker'
    config.min_workers = overrides[:min_workers] || 1
    config.max_workers = overrides[:max_workers] || 10
    config.dry_run = overrides.fetch(:dry_run, true)
    config.enabled = overrides.fetch(:enabled, true)

    overrides.each do |key, value|
      config.send("#{key}=", value) if config.respond_to?("#{key}=")
    end
  end
end

# Test helper to configure with Kubernetes adapter
def configure_kubernetes_autoscaler(overrides = {})
  SolidQueueHerokuAutoscaler.configure do |config|
    config.adapter_class = SolidQueueHerokuAutoscaler::Adapters::Kubernetes
    config.kubernetes_deployment = overrides[:kubernetes_deployment] || 'test-worker'
    config.kubernetes_namespace = overrides[:kubernetes_namespace] || 'default'
    config.kubernetes_context = overrides[:kubernetes_context] || 'test-context'
    config.min_workers = overrides[:min_workers] || 1
    config.max_workers = overrides[:max_workers] || 10
    config.dry_run = overrides.fetch(:dry_run, true)
    config.enabled = overrides.fetch(:enabled, true)

    overrides.each do |key, value|
      config.send("#{key}=", value) if config.respond_to?("#{key}=")
    end
  end
end
