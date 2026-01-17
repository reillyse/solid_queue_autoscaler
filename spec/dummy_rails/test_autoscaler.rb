#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for SolidQueueAutoscaler in a real Rails environment
# Run with: cd spec/dummy_rails && bin/rails runner test_autoscaler.rb

puts "=" * 70
puts "SolidQueueAutoscaler - Real Rails App Integration Test"
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

# Test 2: Verify configurations are loaded
puts "Test 2: Verify configurations are loaded"
begin
  workers = SolidQueueAutoscaler.registered_workers
  if workers.include?(:worker) && workers.include?(:priority_worker)
    puts "  ✓ PASS: Both :worker and :priority_worker configured"
    puts "    Registered workers: #{workers.inspect}"
    results << { test: 'Configurations loaded', passed: true }
  else
    puts "  ✗ FAIL: Expected [:worker, :priority_worker], got #{workers.inspect}"
    results << { test: 'Configurations loaded', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Configurations loaded', passed: false, error: e.message }
end
puts

# Test 3: Verify AutoscaleJob exists and has correct queue
puts "Test 3: Verify AutoscaleJob exists and has correct queue"
begin
  job_class = SolidQueueAutoscaler::AutoscaleJob
  queue_name = job_class.queue_name
  
  if queue_name == 'autoscaler'
    puts "  ✓ PASS: AutoscaleJob.queue_name = '#{queue_name}'"
    results << { test: 'AutoscaleJob queue_name', passed: true }
  else
    puts "  ✗ FAIL: AutoscaleJob.queue_name = '#{queue_name}' (expected 'autoscaler')"
    results << { test: 'AutoscaleJob queue_name', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'AutoscaleJob queue_name', passed: false, error: e.message }
end
puts

# Test 4: Verify job_queue config is respected
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

# Test 5: Enqueue a job and verify the queue
puts "Test 5: Enqueue AutoscaleJob and verify queue"
begin
  # Use test adapter to capture the job without actually running it
  original_adapter = ActiveJob::Base.queue_adapter
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  
  SolidQueueAutoscaler::AutoscaleJob.perform_later(:worker)
  
  enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
  enqueued_queue = enqueued[:queue]
  
  if enqueued_queue == 'autoscaler'
    puts "  ✓ PASS: Job enqueued to '#{enqueued_queue}' queue"
    results << { test: 'Job enqueued to correct queue', passed: true }
  else
    puts "  ✗ FAIL: Job enqueued to '#{enqueued_queue}' (expected 'autoscaler')"
    results << { test: 'Job enqueued to correct queue', passed: false }
  end
  
  # Restore original adapter
  ActiveJob::Base.queue_adapter = original_adapter
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Job enqueued to correct queue', passed: false, error: e.message }
end
puts

# Test 6: Verify job does NOT go to 'default' queue
puts "Test 6: Verify job does NOT go to 'default' queue (REGRESSION TEST)"
begin
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  
  SolidQueueAutoscaler::AutoscaleJob.perform_later
  
  enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
  enqueued_queue = enqueued[:queue]
  
  if enqueued_queue != 'default'
    puts "  ✓ PASS: Job NOT in 'default' queue (actual: '#{enqueued_queue}')"
    results << { test: 'Job not in default queue', passed: true }
  else
    puts "  ✗ FAIL: REGRESSION! Job went to 'default' queue!"
    results << { test: 'Job not in default queue', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Job not in default queue', passed: false, error: e.message }
end
puts

# Test 7: Verify adapter is configured correctly
puts "Test 7: Verify Heroku adapter configuration"
begin
  adapter = SolidQueueAutoscaler.config(:worker).adapter
  if adapter.is_a?(SolidQueueAutoscaler::Adapters::Heroku)
    puts "  ✓ PASS: Adapter is Heroku (#{adapter.class.name})"
    results << { test: 'Heroku adapter configured', passed: true }
  else
    puts "  ✗ FAIL: Adapter is #{adapter.class.name} (expected Heroku)"
    results << { test: 'Heroku adapter configured', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Heroku adapter configured', passed: false, error: e.message }
end
puts

# Test 8: Verify dry_run is enabled
puts "Test 8: Verify dry_run mode"
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

# Test 9: Verify min/max workers configuration
puts "Test 9: Verify min/max workers configuration"
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

# Test 10: Verify process_type configuration
puts "Test 10: Verify process_type configuration"
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

# Test 11: Test job with set(queue:) override
puts "Test 11: Test job with set(queue:) override"
begin
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  
  SolidQueueAutoscaler::AutoscaleJob.set(queue: :custom_override).perform_later(:worker)
  
  enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
  enqueued_queue = enqueued[:queue]
  
  if enqueued_queue == 'custom_override'
    puts "  ✓ PASS: set(queue:) override works (queue='#{enqueued_queue}')"
    results << { test: 'set(queue:) override', passed: true }
  else
    puts "  ✗ FAIL: set(queue:) did not override (got '#{enqueued_queue}')"
    results << { test: 'set(queue:) override', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'set(queue:) override', passed: false, error: e.message }
end
puts

# Test 12: Verify Railtie loaded apply_job_settings!
puts "Test 12: Verify Railtie applied job settings"
begin
  # The Railtie should have called apply_job_settings! after initialization
  # This should have set the queue_name from the config
  job_queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
  config_queue = SolidQueueAutoscaler.config(:worker).job_queue.to_s
  
  if job_queue == config_queue
    puts "  ✓ PASS: Railtie applied job settings (queue='#{job_queue}')"
    results << { test: 'Railtie apply_job_settings!', passed: true }
  else
    puts "  ✗ FAIL: Job queue '#{job_queue}' != config queue '#{config_queue}'"
    results << { test: 'Railtie apply_job_settings!', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Railtie apply_job_settings!', passed: false, error: e.message }
end
puts

# Test 13: Verify SQLite advisory lock support (table-based locking)
puts "Test 13: Verify SQLite advisory lock support"
begin
  # Get the database adapter name
  adapter_name = ActiveRecord::Base.connection.adapter_name
  
  # Create an advisory lock
  lock = SolidQueueAutoscaler::AdvisoryLock.new(
    lock_key: 'test_lock_rails',
    config: SolidQueueAutoscaler.config(:worker)
  )
  
  # Test acquiring the lock
  acquired = lock.try_lock
  
  if acquired
    puts "  ✓ PASS: Advisory lock acquired successfully (adapter: #{adapter_name})"
    
    # Verify we can't acquire it again from a different lock instance
    lock2 = SolidQueueAutoscaler::AdvisoryLock.new(
      lock_key: 'test_lock_rails',
      config: SolidQueueAutoscaler.config(:worker)
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
  adapter_name = ActiveRecord::Base.connection.adapter_name.downcase
  lock = SolidQueueAutoscaler::AdvisoryLock.new(
    lock_key: 'test_strategy_detection',
    config: SolidQueueAutoscaler.config(:worker)
  )
  
  # Access private method to check strategy
  strategy = lock.send(:lock_strategy)
  strategy_class = strategy.class.name
  
  expected_strategy = case adapter_name
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
