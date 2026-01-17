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

# Test 2: Configure workers (simulating Sinatra app.rb)
puts "Test 2: Configure workers"
begin
  SolidQueueAutoscaler.reset_configuration!
  
  SolidQueueAutoscaler.configure(:worker) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-api-key'
    config.heroku_app_name = 'test-app'
    config.process_type = 'worker'
    config.min_workers = 1
    config.max_workers = 5
    config.job_queue = :autoscaler
    config.dry_run = true
    config.enabled = true
  end

  SolidQueueAutoscaler.configure(:priority_worker) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-api-key'
    config.heroku_app_name = 'test-app'
    config.process_type = 'priority_worker'
    config.min_workers = 1
    config.max_workers = 3
    config.job_queue = :autoscaler
    config.dry_run = true
    config.enabled = true
  end

  workers = SolidQueueAutoscaler.registered_workers
  if workers.include?(:worker) && workers.include?(:priority_worker)
    puts "  ✓ PASS: Both :worker and :priority_worker configured"
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
