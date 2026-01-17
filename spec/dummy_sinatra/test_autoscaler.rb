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
