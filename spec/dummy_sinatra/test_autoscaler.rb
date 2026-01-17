#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for SolidQueueAutoscaler in a real Sinatra environment
# Run with: cd spec/dummy_sinatra && bundle exec ruby test_autoscaler.rb

require 'bundler/setup'
require 'active_record'
require 'solid_queue_autoscaler'

puts "=" * 70
puts "SolidQueueAutoscaler - Real Sinatra App Integration Test"
puts "=" * 70
puts

results = []

# Test 1: Verify gem is loaded
puts "Test 1: Verify gem is loaded"
begin
  version = SolidQueueAutoscaler::VERSION
  puts "  ✓ PASS: SolidQueueAutoscaler loaded (version #{version})"
  results << { test: 'Gem loaded', passed: true }
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Gem loaded', passed: false, error: e.message }
end
puts

# Test 2: Configure workers with ALL configuration options (simulating Sinatra app.rb)
puts "Test 2: Configure workers with comprehensive settings"
begin
  SolidQueueAutoscaler.reset_configuration!
  
  SolidQueueAutoscaler.configure(:worker) do |config|
    # Adapter configuration
    config.adapter = :heroku
    config.heroku_api_key = 'test-api-key'
    config.heroku_app_name = 'test-app'
    config.process_type = 'worker'

    # Worker limits
    config.min_workers = 1
    config.max_workers = 5

    # Job settings
    config.job_queue = :autoscaler
    config.job_priority = 10

    # Scaling strategy - fixed
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
    config.lock_key = 'sinatra_worker_lock'
    config.lock_timeout_seconds = 30
  end

  SolidQueueAutoscaler.configure(:priority_worker) do |config|
    # Adapter configuration
    config.adapter = :heroku
    config.heroku_api_key = 'test-api-key'
    config.heroku_app_name = 'test-app'
    config.process_type = 'priority_worker'

    # Worker limits
    config.min_workers = 1
    config.max_workers = 3

    # Job settings
    config.job_queue = :autoscaler
    config.job_priority = 5

    # Scaling strategy - proportional
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
    config.lock_key = 'sinatra_priority_lock'
    config.lock_timeout_seconds = 45
  end

  workers = SolidQueueAutoscaler.registered_workers
  if workers.include?(:worker) && workers.include?(:priority_worker)
    puts "  ✓ PASS: Both :worker and :priority_worker configured with ALL options"
    puts "    Registered workers: #{workers.inspect}"
    results << { test: 'Configure workers', passed: true }
  else
    puts "  ✗ FAIL: Expected [:worker, :priority_worker], got #{workers.inspect}"
    results << { test: 'Configure workers', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Configure workers', passed: false, error: e.message }
end
puts

# Test 3: Verify Heroku adapter is configured
puts "Test 3: Verify Heroku adapter configuration"
begin
  adapter = SolidQueueAutoscaler.config(:worker).adapter
  if adapter.is_a?(SolidQueueAutoscaler::Adapters::Heroku)
    puts "  ✓ PASS: Adapter is Heroku (#{adapter.class.name})"
    results << { test: 'Heroku adapter', passed: true }
  else
    puts "  ✗ FAIL: Adapter is #{adapter.class.name} (expected Heroku)"
    results << { test: 'Heroku adapter', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Heroku adapter', passed: false, error: e.message }
end
puts

# Test 4: Verify job_queue configuration
puts "Test 4: Verify job_queue configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  if worker_config.job_queue.to_s == 'autoscaler'
    puts "  ✓ PASS: config(:worker).job_queue = '#{worker_config.job_queue}'"
    results << { test: 'job_queue config', passed: true }
  else
    puts "  ✗ FAIL: config(:worker).job_queue = '#{worker_config.job_queue}' (expected 'autoscaler')"
    results << { test: 'job_queue config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'job_queue config', passed: false, error: e.message }
end
puts

# Test 5: Verify dry_run is enabled
puts "Test 5: Verify dry_run mode"
begin
  if SolidQueueAutoscaler.config(:worker).dry_run?
    puts "  ✓ PASS: dry_run is enabled (safe for testing)"
    results << { test: 'dry_run enabled', passed: true }
  else
    puts "  ✗ FAIL: dry_run is NOT enabled (dangerous!)"
    results << { test: 'dry_run enabled', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'dry_run enabled', passed: false, error: e.message }
end
puts

# Test 6: Verify min/max workers configuration
puts "Test 6: Verify min/max workers configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.min_workers == 1 && worker_config.max_workers == 5 &&
     priority_config.min_workers == 1 && priority_config.max_workers == 3
    puts "  ✓ PASS: Worker config: min=#{worker_config.min_workers}, max=#{worker_config.max_workers}"
    puts "         Priority config: min=#{priority_config.min_workers}, max=#{priority_config.max_workers}"
    results << { test: 'min/max workers config', passed: true }
  else
    puts "  ✗ FAIL: Worker limits not as expected"
    results << { test: 'min/max workers config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'min/max workers config', passed: false, error: e.message }
end
puts

# Test 7: Verify process_type configuration
puts "Test 7: Verify process_type configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.process_type == 'worker' && priority_config.process_type == 'priority_worker'
    puts "  ✓ PASS: Worker process_type='#{worker_config.process_type}'"
    puts "         Priority process_type='#{priority_config.process_type}'"
    results << { test: 'process_type config', passed: true }
  else
    puts "  ✗ FAIL: process_type not as expected"
    results << { test: 'process_type config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'process_type config', passed: false, error: e.message }
end
puts

# Test 8: Test Kubernetes adapter can be configured
puts "Test 8: Test Kubernetes adapter configuration"
begin
  SolidQueueAutoscaler.configure(:k8s_worker) do |config|
    config.adapter = :kubernetes
    config.kubernetes_deployment = 'worker-deployment'
    config.kubernetes_namespace = 'production'
    config.min_workers = 1
    config.max_workers = 10
    config.dry_run = true
  end
  
  k8s_adapter = SolidQueueAutoscaler.config(:k8s_worker).adapter
  if k8s_adapter.is_a?(SolidQueueAutoscaler::Adapters::Kubernetes)
    puts "  ✓ PASS: Kubernetes adapter configured (#{k8s_adapter.class.name})"
    results << { test: 'Kubernetes adapter', passed: true }
  else
    puts "  ✗ FAIL: Expected Kubernetes adapter, got #{k8s_adapter.class.name}"
    results << { test: 'Kubernetes adapter', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Kubernetes adapter', passed: false, error: e.message }
end
puts

# Test 9: Verify configuration validation
puts "Test 9: Verify configuration validation (missing required fields)"
begin
  SolidQueueAutoscaler.configure(:invalid_worker) do |config|
    config.adapter = :heroku
    # Missing heroku_api_key and heroku_app_name
  end
  puts "  ✗ FAIL: Should have raised ConfigurationError"
  results << { test: 'Config validation', passed: false }
rescue SolidQueueAutoscaler::ConfigurationError => e
  puts "  ✓ PASS: ConfigurationError raised as expected"
  puts "    Error: #{e.message.split("\n").first}"
  results << { test: 'Config validation', passed: true }
rescue => e
  puts "  ✗ FAIL: Unexpected error: #{e.class} - #{e.message}"
  results << { test: 'Config validation', passed: false, error: e.message }
end
puts

# Test 10: Test reset_configuration!
puts "Test 10: Test reset_configuration!"
begin
  initial_count = SolidQueueAutoscaler.registered_workers.size
  SolidQueueAutoscaler.reset_configuration!
  after_reset = SolidQueueAutoscaler.registered_workers.size
  
  if after_reset == 0
    puts "  ✓ PASS: reset_configuration! cleared all workers (#{initial_count} -> #{after_reset})"
    results << { test: 'reset_configuration!', passed: true }
  else
    puts "  ✗ FAIL: Workers not cleared after reset (#{after_reset} remaining)"
    results << { test: 'reset_configuration!', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'reset_configuration!', passed: false, error: e.message }
end
puts

# Test 11: Re-configure and test enabled? flag
puts "Test 11: Test enabled? configuration"
begin
  SolidQueueAutoscaler.configure(:enabled_worker) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.enabled = true
    config.dry_run = true
  end
  
  SolidQueueAutoscaler.configure(:disabled_worker) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.enabled = false
    config.dry_run = true
  end
  
  enabled_config = SolidQueueAutoscaler.config(:enabled_worker)
  disabled_config = SolidQueueAutoscaler.config(:disabled_worker)
  
  if enabled_config.enabled? && !disabled_config.enabled?
    puts "  ✓ PASS: enabled_worker.enabled?=true, disabled_worker.enabled?=false"
    results << { test: 'enabled? config', passed: true }
  else
    puts "  ✗ FAIL: enabled? flags not as expected"
    results << { test: 'enabled? config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'enabled? config', passed: false, error: e.message }
end
puts

# Test 12: Verify adapter name method
puts "Test 12: Verify adapter name method"
begin
  adapter = SolidQueueAutoscaler.config(:enabled_worker).adapter
  adapter_name = adapter.name
  
  if adapter_name == 'Heroku'
    puts "  ✓ PASS: adapter.name = '#{adapter_name}'"
    results << { test: 'adapter.name', passed: true }
  else
    puts "  ✗ FAIL: adapter.name = '#{adapter_name}' (expected 'Heroku')"
    results << { test: 'adapter.name', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'adapter.name', passed: false, error: e.message }
end
puts

# Test 13: Set up database for lock tests
puts "Test 13: Set up SQLite database and test advisory locks"
begin
  # Create an in-memory SQLite database for testing
  ActiveRecord::Base.establish_connection(
    adapter: 'sqlite3',
    database: ':memory:'
  )
  
  # Configure a worker with this connection
  SolidQueueAutoscaler.configure(:lock_test_worker) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.dry_run = true
  end
  
  # Get the database adapter name
  db_adapter_name = ActiveRecord::Base.connection.adapter_name
  
  # Create an advisory lock
  lock = SolidQueueAutoscaler::AdvisoryLock.new(
    lock_key: 'test_lock_sinatra',
    config: SolidQueueAutoscaler.config(:lock_test_worker)
  )
  
  # Test acquiring the lock
  acquired = lock.try_lock
  
  if acquired
    puts "  ✓ PASS: Advisory lock acquired successfully (adapter: #{db_adapter_name})"
    
    # Verify we can't acquire it again from a different lock instance
    lock2 = SolidQueueAutoscaler::AdvisoryLock.new(
      lock_key: 'test_lock_sinatra',
      config: SolidQueueAutoscaler.config(:lock_test_worker)
    )
    acquired2 = lock2.try_lock
    
    if !acquired2
      puts "  ✓ PASS: Second lock correctly blocked"
    else
      puts "  ✗ FAIL: Second lock should have been blocked"
      lock2.release
    end
    
    # Release the lock
    lock.release
    
    # Verify we can acquire it again after release
    acquired3 = lock2.try_lock
    if acquired3
      puts "  ✓ PASS: Lock acquired after release"
      lock2.release
      results << { test: 'SQLite advisory lock', passed: true }
    else
      puts "  ✗ FAIL: Could not acquire lock after release"
      results << { test: 'SQLite advisory lock', passed: false }
    end
  else
    puts "  ✗ FAIL: Could not acquire advisory lock"
    results << { test: 'SQLite advisory lock', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  puts "  Backtrace: #{e.backtrace.first(3).join("\n            ")}"
  results << { test: 'SQLite advisory lock', passed: false, error: e.message }
end
puts

# Test 14: Verify lock strategy detection
puts "Test 14: Verify lock strategy detection"
begin
  db_adapter_name = ActiveRecord::Base.connection.adapter_name.downcase
  lock = SolidQueueAutoscaler::AdvisoryLock.new(
    lock_key: 'test_strategy_detection',
    config: SolidQueueAutoscaler.config(:lock_test_worker)
  )
  
  # Access private method to check strategy
  strategy = lock.send(:lock_strategy)
  strategy_class = strategy.class.name
  
  expected_strategy = case db_adapter_name
  when /sqlite/
    'SolidQueueAutoscaler::AdvisoryLock::SQLiteLockStrategy'
  when /postgresql/, /postgis/
    'SolidQueueAutoscaler::AdvisoryLock::PostgreSQLLockStrategy'
  when /mysql/, /trilogy/
    'SolidQueueAutoscaler::AdvisoryLock::MySQLLockStrategy'
  else
    'SolidQueueAutoscaler::AdvisoryLock::TableBasedLockStrategy'
  end
  
  if strategy_class == expected_strategy
    puts "  ✓ PASS: Correct lock strategy detected (#{strategy_class})"
    results << { test: 'Lock strategy detection', passed: true }
  else
    puts "  ✗ FAIL: Expected #{expected_strategy}, got #{strategy_class}"
    results << { test: 'Lock strategy detection', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Lock strategy detection', passed: false, error: e.message }
end
puts

# Test 15: Verify locks table was auto-created
puts "Test 15: Verify locks table was auto-created"
begin
  table_exists = ActiveRecord::Base.connection.table_exists?('solid_queue_autoscaler_locks')
  
  if table_exists
    puts "  ✓ PASS: Locks table was auto-created"
    
    # Check the table structure
    columns = ActiveRecord::Base.connection.columns('solid_queue_autoscaler_locks').map(&:name)
    expected_columns = %w[lock_key lock_id locked_at locked_by]
    
    if (expected_columns - columns).empty?
      puts "  ✓ PASS: Locks table has correct columns: #{columns.join(', ')}"
      results << { test: 'Locks table auto-created', passed: true }
    else
      puts "  ✗ FAIL: Missing columns: #{(expected_columns - columns).join(', ')}"
      results << { test: 'Locks table auto-created', passed: false }
    end
  else
    puts "  ✗ FAIL: Locks table was not created"
    results << { test: 'Locks table auto-created', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Locks table auto-created', passed: false, error: e.message }
end
puts

# ============================================================================
# COMPREHENSIVE CONFIGURATION TESTS
# Re-configure workers after reset_configuration! test
# ============================================================================

puts "Setting up workers for comprehensive config tests..."
SolidQueueAutoscaler.configure(:worker) do |config|
  config.adapter = :heroku
  config.heroku_api_key = 'test-api-key'
  config.heroku_app_name = 'test-app'
  config.process_type = 'worker'
  config.min_workers = 1
  config.max_workers = 5
  config.job_queue = :autoscaler
  config.job_priority = 10
  config.scaling_strategy = :fixed
  config.scale_up_increment = 2
  config.scale_down_decrement = 1
  config.scale_up_queue_depth = 100
  config.scale_up_latency_seconds = 300
  config.scale_down_queue_depth = 10
  config.scale_down_latency_seconds = 30
  config.cooldown_seconds = 120
  config.scale_up_cooldown_seconds = 60
  config.scale_down_cooldown_seconds = 180
  config.queues = nil
  config.dry_run = true
  config.enabled = true
  config.record_events = true
  config.record_all_events = false
  config.persist_cooldowns = true
  config.table_prefix = 'solid_queue_'
  config.lock_key = 'sinatra_worker_lock'
  config.lock_timeout_seconds = 30
end

SolidQueueAutoscaler.configure(:priority_worker) do |config|
  config.adapter = :heroku
  config.heroku_api_key = 'test-api-key'
  config.heroku_app_name = 'test-app'
  config.process_type = 'priority_worker'
  config.min_workers = 1
  config.max_workers = 3
  config.job_queue = :autoscaler
  config.job_priority = 5
  config.scaling_strategy = :proportional
  config.scale_up_jobs_per_worker = 50
  config.scale_up_latency_per_worker = 60
  config.scale_down_jobs_per_worker = 25
  config.scale_up_queue_depth = 50
  config.scale_up_latency_seconds = 120
  config.scale_down_queue_depth = 5
  config.scale_down_latency_seconds = 15
  config.cooldown_seconds = 60
  config.queues = %w[indexing mailers notifications]
  config.dry_run = true
  config.enabled = true
  config.record_events = true
  config.record_all_events = true
  config.persist_cooldowns = false
  config.table_prefix = 'solid_queue_'
  config.lock_key = 'sinatra_priority_lock'
  config.lock_timeout_seconds = 45
end
puts

# Test 16: Verify job_priority configuration
puts "Test 16: Verify job_priority configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.job_priority == 10 && priority_config.job_priority == 5
    puts "  ✓ PASS: Worker job_priority=#{worker_config.job_priority}, Priority job_priority=#{priority_config.job_priority}"
    results << { test: 'job_priority config', passed: true }
  else
    puts "  ✗ FAIL: job_priority not as expected"
    results << { test: 'job_priority config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'job_priority config', passed: false, error: e.message }
end
puts

# Test 17: Verify scaling_strategy configuration
puts "Test 17: Verify scaling_strategy configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.scaling_strategy == :fixed && priority_config.scaling_strategy == :proportional
    puts "  ✓ PASS: Worker scaling_strategy=:#{worker_config.scaling_strategy}, Priority scaling_strategy=:#{priority_config.scaling_strategy}"
    results << { test: 'scaling_strategy config', passed: true }
  else
    puts "  ✗ FAIL: scaling_strategy not as expected"
    results << { test: 'scaling_strategy config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'scaling_strategy config', passed: false, error: e.message }
end
puts

# Test 18: Verify scale_up thresholds configuration
puts "Test 18: Verify scale_up thresholds configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  worker_ok = worker_config.scale_up_queue_depth == 100 &&
              worker_config.scale_up_latency_seconds == 300 &&
              worker_config.scale_up_increment == 2
  
  priority_ok = priority_config.scale_up_queue_depth == 50 &&
                priority_config.scale_up_latency_seconds == 120 &&
                priority_config.scale_up_jobs_per_worker == 50 &&
                priority_config.scale_up_latency_per_worker == 60
  
  if worker_ok && priority_ok
    puts "  ✓ PASS: Worker scale_up: depth=#{worker_config.scale_up_queue_depth}, latency=#{worker_config.scale_up_latency_seconds}s, increment=#{worker_config.scale_up_increment}"
    puts "         Priority scale_up: depth=#{priority_config.scale_up_queue_depth}, latency=#{priority_config.scale_up_latency_seconds}s, jobs_per_worker=#{priority_config.scale_up_jobs_per_worker}"
    results << { test: 'scale_up thresholds', passed: true }
  else
    puts "  ✗ FAIL: scale_up thresholds not as expected"
    results << { test: 'scale_up thresholds', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'scale_up thresholds', passed: false, error: e.message }
end
puts

# Test 19: Verify scale_down thresholds configuration
puts "Test 19: Verify scale_down thresholds configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  worker_ok = worker_config.scale_down_queue_depth == 10 &&
              worker_config.scale_down_latency_seconds == 30 &&
              worker_config.scale_down_decrement == 1
  
  priority_ok = priority_config.scale_down_queue_depth == 5 &&
                priority_config.scale_down_latency_seconds == 15 &&
                priority_config.scale_down_jobs_per_worker == 25
  
  if worker_ok && priority_ok
    puts "  ✓ PASS: Worker scale_down: depth=#{worker_config.scale_down_queue_depth}, latency=#{worker_config.scale_down_latency_seconds}s, decrement=#{worker_config.scale_down_decrement}"
    puts "         Priority scale_down: depth=#{priority_config.scale_down_queue_depth}, latency=#{priority_config.scale_down_latency_seconds}s, jobs_per_worker=#{priority_config.scale_down_jobs_per_worker}"
    results << { test: 'scale_down thresholds', passed: true }
  else
    puts "  ✗ FAIL: scale_down thresholds not as expected"
    results << { test: 'scale_down thresholds', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'scale_down thresholds', passed: false, error: e.message }
end
puts

# Test 20: Verify cooldown settings configuration
puts "Test 20: Verify cooldown settings configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  worker_ok = worker_config.cooldown_seconds == 120 &&
              worker_config.scale_up_cooldown_seconds == 60 &&
              worker_config.scale_down_cooldown_seconds == 180 &&
              worker_config.effective_scale_up_cooldown == 60 &&
              worker_config.effective_scale_down_cooldown == 180
  
  # Priority uses defaults (cooldown_seconds only)
  priority_ok = priority_config.cooldown_seconds == 60 &&
                priority_config.effective_scale_up_cooldown == 60 &&
                priority_config.effective_scale_down_cooldown == 60
  
  if worker_ok && priority_ok
    puts "  ✓ PASS: Worker cooldowns: base=#{worker_config.cooldown_seconds}s, up=#{worker_config.effective_scale_up_cooldown}s, down=#{worker_config.effective_scale_down_cooldown}s"
    puts "         Priority cooldowns: base=#{priority_config.cooldown_seconds}s, effective_up=#{priority_config.effective_scale_up_cooldown}s, effective_down=#{priority_config.effective_scale_down_cooldown}s"
    results << { test: 'cooldown settings', passed: true }
  else
    puts "  ✗ FAIL: cooldown settings not as expected"
    results << { test: 'cooldown settings', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'cooldown settings', passed: false, error: e.message }
end
puts

# Test 21: Verify queues filter configuration
puts "Test 21: Verify queues filter configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  worker_ok = worker_config.queues.nil?  # nil = all queues
  priority_ok = priority_config.queues == %w[indexing mailers notifications]
  
  if worker_ok && priority_ok
    puts "  ✓ PASS: Worker queues=nil (all queues)"
    puts "         Priority queues=#{priority_config.queues.inspect}"
    results << { test: 'queues filter', passed: true }
  else
    puts "  ✗ FAIL: queues filter not as expected"
    results << { test: 'queues filter', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'queues filter', passed: false, error: e.message }
end
puts

# Test 22: Verify record_events configuration
puts "Test 22: Verify record_events configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  # Note: record_events? depends on connection_available?, so check raw values
  worker_ok = worker_config.record_events == true && worker_config.record_all_events == false
  priority_ok = priority_config.record_events == true && priority_config.record_all_events == true
  
  if worker_ok && priority_ok
    puts "  ✓ PASS: Worker record_events=#{worker_config.record_events}, record_all_events=#{worker_config.record_all_events}"
    puts "         Priority record_events=#{priority_config.record_events}, record_all_events=#{priority_config.record_all_events}"
    results << { test: 'record_events config', passed: true }
  else
    puts "  ✗ FAIL: record_events config not as expected"
    results << { test: 'record_events config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'record_events config', passed: false, error: e.message }
end
puts

# Test 23: Verify persist_cooldowns configuration
puts "Test 23: Verify persist_cooldowns configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.persist_cooldowns == true && priority_config.persist_cooldowns == false
    puts "  ✓ PASS: Worker persist_cooldowns=#{worker_config.persist_cooldowns}, Priority persist_cooldowns=#{priority_config.persist_cooldowns}"
    results << { test: 'persist_cooldowns config', passed: true }
  else
    puts "  ✗ FAIL: persist_cooldowns not as expected"
    results << { test: 'persist_cooldowns config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'persist_cooldowns config', passed: false, error: e.message }
end
puts

# Test 24: Verify table_prefix configuration
puts "Test 24: Verify table_prefix configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.table_prefix == 'solid_queue_' && priority_config.table_prefix == 'solid_queue_'
    puts "  ✓ PASS: Worker table_prefix='#{worker_config.table_prefix}', Priority table_prefix='#{priority_config.table_prefix}'"
    results << { test: 'table_prefix config', passed: true }
  else
    puts "  ✗ FAIL: table_prefix not as expected"
    results << { test: 'table_prefix config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'table_prefix config', passed: false, error: e.message }
end
puts

# Test 25: Verify lock_key configuration
puts "Test 25: Verify lock_key configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.lock_key == 'sinatra_worker_lock' && priority_config.lock_key == 'sinatra_priority_lock'
    puts "  ✓ PASS: Worker lock_key='#{worker_config.lock_key}', Priority lock_key='#{priority_config.lock_key}'"
    results << { test: 'lock_key config', passed: true }
  else
    puts "  ✗ FAIL: lock_key not as expected (worker=#{worker_config.lock_key}, priority=#{priority_config.lock_key})"
    results << { test: 'lock_key config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'lock_key config', passed: false, error: e.message }
end
puts

# Test 26: Verify lock_timeout_seconds configuration
puts "Test 26: Verify lock_timeout_seconds configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.lock_timeout_seconds == 30 && priority_config.lock_timeout_seconds == 45
    puts "  ✓ PASS: Worker lock_timeout=#{worker_config.lock_timeout_seconds}s, Priority lock_timeout=#{priority_config.lock_timeout_seconds}s"
    results << { test: 'lock_timeout_seconds config', passed: true }
  else
    puts "  ✗ FAIL: lock_timeout_seconds not as expected"
    results << { test: 'lock_timeout_seconds config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'lock_timeout_seconds config', passed: false, error: e.message }
end
puts

# Test 27: Verify config can be retrieved by name
puts "Test 27: Verify config retrieval by worker name"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.name == :worker && priority_config.name == :priority_worker
    puts "  ✓ PASS: Config names are correctly set (worker.name=:#{worker_config.name}, priority.name=:#{priority_config.name})"
    results << { test: 'config name retrieval', passed: true }
  else
    puts "  ✗ FAIL: Config names not as expected"
    results << { test: 'config name retrieval', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'config name retrieval', passed: false, error: e.message }
end
puts

# ============================================================================
# DECISION ENGINE THRESHOLD TESTS
# Verify the decision engine uses configured thresholds correctly
# ============================================================================

# Helper to create mock metrics
def create_mock_metrics(queue_depth:, latency:, claimed_jobs: 0)
  SolidQueueAutoscaler::Metrics::Result.new(
    queue_depth: queue_depth,
    oldest_job_age_seconds: latency,
    jobs_per_minute: 10,
    claimed_jobs: claimed_jobs,
    failed_jobs: 0,
    blocked_jobs: 0,
    active_workers: 2,
    queues_breakdown: { 'default' => queue_depth },
    collected_at: Time.now
  )
end

# Test 28: Decision engine scales up when queue_depth >= threshold
puts "Test 28: Decision engine scales up when queue_depth >= scale_up_queue_depth"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  
  # Worker config has scale_up_queue_depth = 100
  # Create metrics with queue_depth = 100 (at threshold)
  metrics = create_mock_metrics(queue_depth: 100, latency: 10)
  decision = engine.decide(metrics: metrics, current_workers: 2)
  
  if decision.action == :scale_up
    puts "  ✓ PASS: Decision engine correctly scales up when queue_depth=100 (threshold=#{worker_config.scale_up_queue_depth})"
    puts "         Decision: #{decision.action}, from=#{decision.from}, to=#{decision.to}"
    results << { test: 'decision engine scale_up queue_depth', passed: true }
  else
    puts "  ✗ FAIL: Expected scale_up but got #{decision.action}"
    results << { test: 'decision engine scale_up queue_depth', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'decision engine scale_up queue_depth', passed: false, error: e.message }
end
puts

# Test 29: Decision engine scales up when latency >= threshold
puts "Test 29: Decision engine scales up when latency >= scale_up_latency_seconds"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  
  # Worker config has scale_up_latency_seconds = 300
  # Create metrics with latency = 300 (at threshold), low queue_depth
  metrics = create_mock_metrics(queue_depth: 5, latency: 300)
  decision = engine.decide(metrics: metrics, current_workers: 2)
  
  if decision.action == :scale_up
    puts "  ✓ PASS: Decision engine correctly scales up when latency=300s (threshold=#{worker_config.scale_up_latency_seconds}s)"
    puts "         Decision: #{decision.action}, from=#{decision.from}, to=#{decision.to}"
    results << { test: 'decision engine scale_up latency', passed: true }
  else
    puts "  ✗ FAIL: Expected scale_up but got #{decision.action}"
    results << { test: 'decision engine scale_up latency', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'decision engine scale_up latency', passed: false, error: e.message }
end
puts

# Test 30: Decision engine scales down when both thresholds are low
puts "Test 30: Decision engine scales down when queue_depth AND latency are low"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  
  # Worker config has scale_down_queue_depth = 10, scale_down_latency_seconds = 30
  # Create metrics at or below both thresholds
  metrics = create_mock_metrics(queue_depth: 10, latency: 30)
  decision = engine.decide(metrics: metrics, current_workers: 3)
  
  if decision.action == :scale_down
    puts "  ✓ PASS: Decision engine correctly scales down when queue_depth=#{metrics.queue_depth} (threshold=#{worker_config.scale_down_queue_depth}) AND latency=#{metrics.oldest_job_age_seconds.to_i}s (threshold=#{worker_config.scale_down_latency_seconds}s)"
    puts "         Decision: #{decision.action}, from=#{decision.from}, to=#{decision.to}"
    results << { test: 'decision engine scale_down', passed: true }
  else
    puts "  ✗ FAIL: Expected scale_down but got #{decision.action}"
    results << { test: 'decision engine scale_down', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'decision engine scale_down', passed: false, error: e.message }
end
puts

# Test 31: Decision engine returns no_change when metrics are in normal range
puts "Test 31: Decision engine returns no_change when metrics are in normal range"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  
  # Create metrics between scale_up and scale_down thresholds
  # queue_depth: between 10 (down) and 100 (up) -> use 50
  # latency: between 30s (down) and 300s (up) -> use 100s
  metrics = create_mock_metrics(queue_depth: 50, latency: 100)
  decision = engine.decide(metrics: metrics, current_workers: 3)
  
  if decision.action == :no_change
    puts "  ✓ PASS: Decision engine correctly returns no_change for normal metrics"
    puts "         queue_depth=#{metrics.queue_depth} (between #{worker_config.scale_down_queue_depth}-#{worker_config.scale_up_queue_depth})"
    puts "         latency=#{metrics.oldest_job_age_seconds.to_i}s (between #{worker_config.scale_down_latency_seconds}s-#{worker_config.scale_up_latency_seconds}s)"
    results << { test: 'decision engine no_change normal', passed: true }
  else
    puts "  ✗ FAIL: Expected no_change but got #{decision.action}"
    results << { test: 'decision engine no_change normal', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'decision engine no_change normal', passed: false, error: e.message }
end
puts

# Test 32: Decision engine respects max_workers limit
puts "Test 32: Decision engine respects max_workers limit (no scale_up at max)"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  
  # Create metrics that would trigger scale_up
  metrics = create_mock_metrics(queue_depth: 200, latency: 500)
  # But we're already at max_workers (5 for worker config)
  decision = engine.decide(metrics: metrics, current_workers: worker_config.max_workers)
  
  if decision.action == :no_change && decision.reason.include?('max_workers')
    puts "  ✓ PASS: Decision engine respects max_workers (#{worker_config.max_workers})"
    puts "         Decision: #{decision.action}, reason: #{decision.reason}"
    results << { test: 'decision engine max_workers', passed: true }
  else
    puts "  ✗ FAIL: Expected no_change at max_workers but got #{decision.action}"
    results << { test: 'decision engine max_workers', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'decision engine max_workers', passed: false, error: e.message }
end
puts

# Test 33: Decision engine respects min_workers limit
puts "Test 33: Decision engine respects min_workers limit (no scale_down at min)"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  
  # Create metrics that would trigger scale_down (idle queue)
  metrics = create_mock_metrics(queue_depth: 0, latency: 0, claimed_jobs: 0)
  # But we're already at min_workers (1 for worker config)
  decision = engine.decide(metrics: metrics, current_workers: worker_config.min_workers)
  
  if decision.action == :no_change && decision.reason.include?('min_workers')
    puts "  ✓ PASS: Decision engine respects min_workers (#{worker_config.min_workers})"
    puts "         Decision: #{decision.action}, reason: #{decision.reason}"
    results << { test: 'decision engine min_workers', passed: true }
  else
    puts "  ✗ FAIL: Expected no_change at min_workers but got #{decision.action}"
    results << { test: 'decision engine min_workers', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'decision engine min_workers', passed: false, error: e.message }
end
puts

# Test 34: Priority worker uses different thresholds than main worker
puts "Test 34: Priority worker uses different (lower) thresholds"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  worker_engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  priority_engine = SolidQueueAutoscaler::DecisionEngine.new(config: priority_config)
  
  # Create metrics that trigger scale_up for priority but not worker
  # Priority: scale_up_queue_depth = 50, worker: scale_up_queue_depth = 100
  metrics = create_mock_metrics(queue_depth: 60, latency: 100)
  
  worker_decision = worker_engine.decide(metrics: metrics, current_workers: 2)
  priority_decision = priority_engine.decide(metrics: metrics, current_workers: 2)
  
  # Priority should scale up (60 >= 50), worker should not (60 < 100)
  if priority_decision.action == :scale_up && worker_decision.action != :scale_up
    puts "  ✓ PASS: Different workers use different thresholds"
    puts "         Priority (threshold=#{priority_config.scale_up_queue_depth}): #{priority_decision.action}"
    puts "         Worker (threshold=#{worker_config.scale_up_queue_depth}): #{worker_decision.action}"
    results << { test: 'different worker thresholds', passed: true }
  else
    puts "  ✗ FAIL: Expected priority=scale_up, worker=no_change"
    puts "         Got priority=#{priority_decision.action}, worker=#{worker_decision.action}"
    results << { test: 'different worker thresholds', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'different worker thresholds', passed: false, error: e.message }
end
puts

# Test 35: Fixed scaling strategy adds exactly scale_up_increment
puts "Test 35: Fixed scaling strategy adds exactly scale_up_increment workers"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  
  # Worker uses :fixed strategy with scale_up_increment = 2
  metrics = create_mock_metrics(queue_depth: 150, latency: 400)
  decision = engine.decide(metrics: metrics, current_workers: 2)
  
  expected_target = 2 + worker_config.scale_up_increment
  
  if decision.action == :scale_up && decision.to == expected_target
    puts "  ✓ PASS: Fixed strategy adds exactly #{worker_config.scale_up_increment} workers"
    puts "         Decision: from=#{decision.from} to=#{decision.to} (increment=#{worker_config.scale_up_increment})"
    results << { test: 'fixed scaling increment', passed: true }
  else
    puts "  ✗ FAIL: Expected to=#{expected_target} but got to=#{decision.to}"
    results << { test: 'fixed scaling increment', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'fixed scaling increment', passed: false, error: e.message }
end
puts

# Test 36: Proportional scaling strategy (priority_worker uses proportional)
puts "Test 36: Proportional scaling strategy calculates workers based on load"
begin
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: priority_config)
  
  # Priority worker uses :proportional strategy
  # scale_up_queue_depth = 50, scale_up_jobs_per_worker = 50
  # Create metrics with 150 jobs over threshold (200 - 50 = 150)
  # 150 / 50 = 3 workers to add
  metrics = create_mock_metrics(queue_depth: 200, latency: 200)
  decision = engine.decide(metrics: metrics, current_workers: 1)
  
  if decision.action == :scale_up && decision.to > 2
    puts "  ✓ PASS: Proportional strategy calculates workers based on load"
    puts "         Queue depth=#{metrics.queue_depth}, threshold=#{priority_config.scale_up_queue_depth}"
    puts "         Decision: from=#{decision.from} to=#{decision.to}"
    puts "         Reason: #{decision.reason}"
    results << { test: 'proportional scaling', passed: true }
  else
    puts "  ✗ FAIL: Expected proportional scale_up to more than 2 workers"
    results << { test: 'proportional scaling', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'proportional scaling', passed: false, error: e.message }
end
puts

# Test 37: Scale down requires BOTH conditions to be met
puts "Test 37: Scale down requires BOTH queue_depth AND latency to be low"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  
  # scale_down_queue_depth = 10, scale_down_latency_seconds = 30
  # Create metrics with low queue_depth but high latency
  metrics = create_mock_metrics(queue_depth: 5, latency: 100)
  decision = engine.decide(metrics: metrics, current_workers: 3)
  
  if decision.action == :no_change
    puts "  ✓ PASS: Scale down requires BOTH conditions (low queue AND low latency)"
    puts "         queue_depth=#{metrics.queue_depth} (threshold=#{worker_config.scale_down_queue_depth}) - LOW"
    puts "         latency=#{metrics.oldest_job_age_seconds.to_i}s (threshold=#{worker_config.scale_down_latency_seconds}s) - HIGH"
    puts "         Decision: #{decision.action}"
    results << { test: 'scale_down requires both', passed: true }
  else
    puts "  ✗ FAIL: Expected no_change but got #{decision.action}"
    results << { test: 'scale_down requires both', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'scale_down requires both', passed: false, error: e.message }
end
puts

# Test 38: Scale up requires EITHER condition to be met
puts "Test 38: Scale up requires EITHER queue_depth OR latency to be high"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  
  # scale_up_queue_depth = 100, scale_up_latency_seconds = 300
  # Test 1: High queue_depth, low latency -> should scale up
  metrics1 = create_mock_metrics(queue_depth: 150, latency: 50)
  decision1 = engine.decide(metrics: metrics1, current_workers: 2)
  
  # Test 2: Low queue_depth, high latency -> should also scale up
  metrics2 = create_mock_metrics(queue_depth: 20, latency: 400)
  decision2 = engine.decide(metrics: metrics2, current_workers: 2)
  
  if decision1.action == :scale_up && decision2.action == :scale_up
    puts "  ✓ PASS: Scale up triggers on EITHER high queue_depth OR high latency"
    puts "         Test 1: queue_depth=#{metrics1.queue_depth} (HIGH), latency=#{metrics1.oldest_job_age_seconds.to_i}s (LOW) -> #{decision1.action}"
    puts "         Test 2: queue_depth=#{metrics2.queue_depth} (LOW), latency=#{metrics2.oldest_job_age_seconds.to_i}s (HIGH) -> #{decision2.action}"
    results << { test: 'scale_up requires either', passed: true }
  else
    puts "  ✗ FAIL: Expected both to scale_up"
    results << { test: 'scale_up requires either', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'scale_up requires either', passed: false, error: e.message }
end
puts

# Test 39: Decision reason includes threshold values
puts "Test 39: Decision reason includes configured threshold values"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  engine = SolidQueueAutoscaler::DecisionEngine.new(config: worker_config)
  
  metrics = create_mock_metrics(queue_depth: 150, latency: 400)
  decision = engine.decide(metrics: metrics, current_workers: 2)
  
  # The reason should include the actual threshold value (100)
  if decision.reason.include?(worker_config.scale_up_queue_depth.to_s) || 
     decision.reason.include?(worker_config.scale_up_latency_seconds.to_s)
    puts "  ✓ PASS: Decision reason includes threshold values"
    puts "         Reason: #{decision.reason}"
    results << { test: 'decision reason thresholds', passed: true }
  else
    puts "  ✗ FAIL: Decision reason should include threshold values"
    puts "         Reason: #{decision.reason}"
    results << { test: 'decision reason thresholds', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'decision reason thresholds', passed: false, error: e.message }
end
puts

# ============================================================================
# END-TO-END INTEGRATION TESTS WITH MOCKED HEROKU API
# These tests verify the full scaling workflow with mocked PlatformAPI
# ============================================================================

# Mock PlatformAPI classes for end-to-end testing
class MockFormation
  attr_reader :calls
  
  def initialize(initial_quantity: 2)
    @quantity = initial_quantity
    @calls = []
  end
  
  def info(app_name, process_type)
    @calls << { method: :info, app_name: app_name, process_type: process_type }
    { 'quantity' => @quantity, 'type' => process_type, 'size' => 'standard-1x' }
  end
  
  def update(app_name, process_type, params)
    @calls << { method: :update, app_name: app_name, process_type: process_type, quantity: params[:quantity] }
    @quantity = params[:quantity]
    { 'quantity' => @quantity }
  end
  
  def list(app_name)
    @calls << { method: :list, app_name: app_name }
    [{ 'type' => 'worker', 'quantity' => @quantity, 'size' => 'standard-1x' }]
  end
end

class MockPlatformClient
  attr_reader :formation
  
  def initialize(initial_quantity: 2)
    @formation = MockFormation.new(initial_quantity: initial_quantity)
  end
end

# Helper to create a test config with mocked adapter for Sinatra
def create_sinatra_e2e_config(name:, mock_client:)
  config = SolidQueueAutoscaler::Configuration.new.tap do |c|
    c.name = name
    c.heroku_api_key = 'sinatra-test-api-key'
    c.heroku_app_name = 'sinatra-test-app'
    c.process_type = 'worker'
    c.min_workers = 1
    c.max_workers = 10
    c.scale_up_queue_depth = 100
    c.scale_up_latency_seconds = 300
    c.scale_up_increment = 2
    c.scale_down_queue_depth = 10
    c.scale_down_latency_seconds = 30
    c.scale_down_decrement = 1
    c.cooldown_seconds = 60
    c.dry_run = false
    c.enabled = true
    c.persist_cooldowns = false
    c.record_events = false
    c.logger = Logger.new(STDOUT).tap { |l| l.level = Logger::WARN }
  end
  
  adapter = SolidQueueAutoscaler::Adapters::Heroku.new(config: config)
  adapter.instance_variable_set(:@client, mock_client)
  config.adapter = adapter
  
  config
end

# Mock metrics collector for E2E tests
class MockMetricsCollector
  def initialize(metrics)
    @metrics = metrics
  end
  
  def collect
    @metrics
  end
end

# Test 40: E2E - Full scale up workflow with mocked Heroku API (Sinatra)
puts "Test 40: E2E - Full scale up workflow with mocked Heroku API"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  e2e_config = create_sinatra_e2e_config(name: :sinatra_e2e_up, mock_client: mock_client)
  
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  unless result.success? && result.scaled?
    passed = false
    issues << "Should have scaled successfully"
  end
  
  unless result.decision.action == :scale_up
    passed = false
    issues << "Decision should be :scale_up"
  end
  
  unless result.decision.from == 2 && result.decision.to == 4
    passed = false
    issues << "Should scale from 2 to 4 workers"
  end
  
  update_calls = mock_client.formation.calls.select { |c| c[:method] == :update }
  unless update_calls.length >= 1 && update_calls.last[:quantity] == 4
    passed = false
    issues << "Heroku API should be called with quantity=4"
  end
  
  if passed
    puts "  ✓ PASS: Full scale up workflow completed successfully"
    puts "         Decision: #{result.decision.from} -> #{result.decision.to} workers"
    results << { test: 'E2E scale up workflow', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E scale up workflow', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E scale up workflow', passed: false, error: e.message }
end
puts

# Test 41: E2E - Full scale down workflow (Sinatra)
puts "Test 41: E2E - Full scale down workflow with mocked Heroku API"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 5)
  e2e_config = create_sinatra_e2e_config(name: :sinatra_e2e_down, mock_client: mock_client)
  
  low_metrics = create_mock_metrics(queue_depth: 5, latency: 10)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(low_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  unless result.success? && result.scaled?
    passed = false
    issues << "Should have scaled successfully"
  end
  
  unless result.decision.action == :scale_down
    passed = false
    issues << "Decision should be :scale_down"
  end
  
  unless result.decision.from == 5 && result.decision.to == 4
    passed = false
    issues << "Should scale from 5 to 4"
  end
  
  if passed
    puts "  ✓ PASS: Full scale down workflow completed successfully"
    puts "         Decision: #{result.decision.from} -> #{result.decision.to} workers"
    results << { test: 'E2E scale down workflow', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E scale down workflow', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E scale down workflow', passed: false, error: e.message }
end
puts

# Test 42: E2E - No change when metrics are normal (Sinatra)
puts "Test 42: E2E - No change when metrics are in normal range"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 3)
  e2e_config = create_sinatra_e2e_config(name: :sinatra_e2e_normal, mock_client: mock_client)
  
  normal_metrics = create_mock_metrics(queue_depth: 50, latency: 100)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(normal_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  unless result.success? && !result.scaled?
    passed = false
    issues << "Should succeed without scaling"
  end
  
  unless result.decision.action == :no_change
    passed = false
    issues << "Decision should be :no_change"
  end
  
  update_calls = mock_client.formation.calls.select { |c| c[:method] == :update }
  unless update_calls.empty?
    passed = false
    issues << "Should not call Heroku update API"
  end
  
  if passed
    puts "  ✓ PASS: No change when metrics are normal"
    puts "         Reason: #{result.decision.reason}"
    results << { test: 'E2E no change workflow', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E no change workflow', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E no change workflow', passed: false, error: e.message }
end
puts

# Test 43: E2E - Cooldown enforcement (Sinatra)
puts "Test 43: E2E - Cooldown prevents rapid scaling"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  e2e_config = create_sinatra_e2e_config(name: :sinatra_e2e_cooldown, mock_client: mock_client)
  e2e_config.cooldown_seconds = 60
  
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  # First scaling should succeed
  result1 = scaler.run
  
  # Update mock client for second run
  mock_client2 = MockPlatformClient.new(initial_quantity: 4)
  e2e_config.adapter.instance_variable_set(:@client, mock_client2)
  
  # Second scaling immediately after should be blocked
  result2 = scaler.run
  
  passed = true
  issues = []
  
  unless result1.scaled?
    passed = false
    issues << "First scaling should succeed"
  end
  
  unless result2.skipped?
    passed = false
    issues << "Second scaling should be skipped"
  end
  
  if result2.skipped? && !result2.skipped_reason.include?('Cooldown')
    passed = false
    issues << "Skip reason should mention cooldown"
  end
  
  if passed
    puts "  ✓ PASS: Cooldown prevents rapid scaling"
    puts "         First: scaled=#{result1.scaled?}, Second: skipped=#{result2.skipped?}"
    results << { test: 'E2E cooldown enforcement', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E cooldown enforcement', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E cooldown enforcement', passed: false, error: e.message }
end
puts

# Test 44: E2E - Max workers limit (Sinatra)
puts "Test 44: E2E - Max workers limit is respected"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 10)
  e2e_config = create_sinatra_e2e_config(name: :sinatra_e2e_max, mock_client: mock_client)
  e2e_config.max_workers = 10
  
  very_high_metrics = create_mock_metrics(queue_depth: 500, latency: 600)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(very_high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  unless result.success? && !result.scaled?
    passed = false
    issues << "Should not scale past max"
  end
  
  unless result.decision.reason.include?('max_workers')
    passed = false
    issues << "Reason should mention max_workers"
  end
  
  if passed
    puts "  ✓ PASS: Max workers limit is respected"
    puts "         Reason: #{result.decision.reason}"
    results << { test: 'E2E max workers limit', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E max workers limit', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E max workers limit', passed: false, error: e.message }
end
puts

# Test 45: E2E - Min workers limit (Sinatra)
puts "Test 45: E2E - Min workers limit is respected"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 1)
  e2e_config = create_sinatra_e2e_config(name: :sinatra_e2e_min, mock_client: mock_client)
  e2e_config.min_workers = 1
  
  idle_metrics = create_mock_metrics(queue_depth: 0, latency: 0, claimed_jobs: 0)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(idle_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  unless result.success? && !result.scaled?
    passed = false
    issues << "Should not scale below min"
  end
  
  unless result.decision.reason.include?('min_workers')
    passed = false
    issues << "Reason should mention min_workers"
  end
  
  if passed
    puts "  ✓ PASS: Min workers limit is respected"
    puts "         Reason: #{result.decision.reason}"
    results << { test: 'E2E min workers limit', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E min workers limit', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E min workers limit', passed: false, error: e.message }
end
puts

# Test 46: E2E - Result object completeness (Sinatra)
puts "Test 46: E2E - Result object contains all expected data"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  e2e_config = create_sinatra_e2e_config(name: :sinatra_e2e_result, mock_client: mock_client)
  
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  # Verify all expected fields exist
  unless result.respond_to?(:success) && result.respond_to?(:decision) && result.respond_to?(:metrics)
    passed = false
    issues << "Missing basic fields"
  end
  
  unless result.decision.respond_to?(:action) && result.decision.respond_to?(:from) && result.decision.respond_to?(:to) && result.decision.respond_to?(:reason)
    passed = false
    issues << "Decision missing fields"
  end
  
  unless result.metrics.respond_to?(:queue_depth) && result.metrics.respond_to?(:oldest_job_age_seconds)
    passed = false
    issues << "Metrics missing fields"
  end
  
  unless result.respond_to?(:executed_at) && result.executed_at.is_a?(Time)
    passed = false
    issues << "Missing executed_at timestamp"
  end
  
  if passed
    puts "  ✓ PASS: Result object contains all expected data"
    puts "         success=#{result.success}, action=#{result.decision.action}"
    puts "         from=#{result.decision.from}, to=#{result.decision.to}"
    results << { test: 'E2E result completeness', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E result completeness', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E result completeness', passed: false, error: e.message }
end
puts

# Test 47: E2E - Verify adapter receives correct app/process parameters (Sinatra)
puts "Test 47: E2E - Adapter receives correct app name and process type"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  
  config = SolidQueueAutoscaler::Configuration.new.tap do |c|
    c.name = :sinatra_e2e_params
    c.heroku_api_key = 'test-key'
    c.heroku_app_name = 'sinatra-custom-app'
    c.process_type = 'sidekiq'
    c.min_workers = 1
    c.max_workers = 10
    c.scale_up_queue_depth = 100
    c.scale_up_increment = 1
    c.cooldown_seconds = 60
    c.dry_run = false
    c.enabled = true
    c.persist_cooldowns = false
    c.record_events = false
    c.logger = Logger.new(STDOUT).tap { |l| l.level = Logger::WARN }
  end
  
  adapter = SolidQueueAutoscaler::Adapters::Heroku.new(config: config)
  adapter.instance_variable_set(:@client, mock_client)
  config.adapter = adapter
  
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  # Check API calls used correct parameters
  mock_client.formation.calls.each do |call|
    if call[:app_name] != 'sinatra-custom-app'
      passed = false
      issues << "Wrong app_name: #{call[:app_name]}"
    end
    if call[:process_type] != 'sidekiq'
      passed = false
      issues << "Wrong process_type: #{call[:process_type]}"
    end
  end
  
  if passed
    puts "  ✓ PASS: Adapter receives correct app name and process type"
    puts "         app_name='sinatra-custom-app', process_type='sidekiq'"
    results << { test: 'E2E adapter parameters', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E adapter parameters', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E adapter parameters', passed: false, error: e.message }
end
puts

# Test 48: E2E - Disabled autoscaler returns skipped (Sinatra)
puts "Test 48: E2E - Disabled autoscaler returns skipped result"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  e2e_config = create_sinatra_e2e_config(name: :sinatra_e2e_disabled, mock_client: mock_client)
  e2e_config.enabled = false
  
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  result = scaler.run
  
  passed = true
  issues = []
  
  unless result.skipped?
    passed = false
    issues << "Should be skipped when disabled"
  end
  
  unless result.skipped_reason.include?('disabled')
    passed = false
    issues << "Reason should mention disabled"
  end
  
  # Verify no API calls were made
  unless mock_client.formation.calls.empty?
    passed = false
    issues << "Should not call Heroku API when disabled"
  end
  
  if passed
    puts "  ✓ PASS: Disabled autoscaler returns skipped result"
    puts "         Reason: #{result.skipped_reason}"
    results << { test: 'E2E disabled autoscaler', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E disabled autoscaler', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E disabled autoscaler', passed: false, error: e.message }
end
puts

# Test 49: E2E - Dry run mode (Sinatra)
puts "Test 49: E2E - Dry run mode logs but adapter handles it"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  e2e_config = create_sinatra_e2e_config(name: :sinatra_e2e_dryrun, mock_client: mock_client)
  e2e_config.dry_run = true
  
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  unless result.success?
    passed = false
    issues << "Should succeed in dry run"
  end
  
  unless result.decision.action == :scale_up
    passed = false
    issues << "Decision should still be :scale_up"
  end
  
  if passed
    puts "  ✓ PASS: Dry run mode works correctly"
    puts "         Decision: #{result.decision.action}"
    results << { test: 'E2E dry run mode', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E dry run mode', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E dry run mode', passed: false, error: e.message }
end
puts

# Summary
puts "=" * 70
puts "SUMMARY"
puts "=" * 70
passed = results.count { |r| r[:passed] }
failed = results.count { |r| !r[:passed] }
puts "Total: #{results.size} tests"
puts "Passed: #{passed}"
puts "Failed: #{failed}"
puts

if failed > 0
  puts "FAILED TESTS:"
  results.select { |r| !r[:passed] }.each do |r|
    puts "  - #{r[:test]}: #{r[:error]}"
  end
  exit 1
else
  puts "ALL TESTS PASSED! ✓"
  exit 0
end
