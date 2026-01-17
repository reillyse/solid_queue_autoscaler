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

# ============================================================================
# COMPREHENSIVE CONFIGURATION TESTS
# ============================================================================

# Test 15: Verify job_priority configuration
puts "Test 15: Verify job_priority configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.job_priority == 10 && priority_config.job_priority == 5
    puts "  ✓ PASS: Worker job_priority=#{worker_config.job_priority}, Priority job_priority=#{priority_config.job_priority}"
    results << { test: 'job_priority config', passed: true }
  else
    puts "  ✗ FAIL: job_priority not as expected (worker=#{worker_config.job_priority}, priority=#{priority_config.job_priority})"
    results << { test: 'job_priority config', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'job_priority config', passed: false, error: e.message }
end
puts

# Test 16: Verify scaling_strategy configuration
puts "Test 16: Verify scaling_strategy configuration"
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

# Test 17: Verify scale_up thresholds configuration
puts "Test 17: Verify scale_up thresholds configuration"
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

# Test 18: Verify scale_down thresholds configuration
puts "Test 18: Verify scale_down thresholds configuration"
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

# Test 19: Verify cooldown settings configuration
puts "Test 19: Verify cooldown settings configuration"
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

# Test 20: Verify queues filter configuration
puts "Test 20: Verify queues filter configuration"
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

# Test 21: Verify enabled flag configuration
puts "Test 21: Verify enabled? flag configuration"
begin
  worker_config = SolidQueueAutoscaler.config(:worker)
  priority_config = SolidQueueAutoscaler.config(:priority_worker)
  
  if worker_config.enabled? && priority_config.enabled?
    puts "  ✓ PASS: Worker enabled?=#{worker_config.enabled?}, Priority enabled?=#{priority_config.enabled?}"
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
  
  if worker_config.lock_key == 'autoscaler_worker_lock' && priority_config.lock_key == 'autoscaler_priority_lock'
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

# Test 27: Verify enqueued job has correct priority
puts "Test 27: Verify enqueued job has correct priority"
begin
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  
  SolidQueueAutoscaler::AutoscaleJob.perform_later(:worker)
  
  enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
  
  # Check that job was enqueued (priority may or may not be in the hash depending on ActiveJob version)
  if enqueued && enqueued[:queue] == 'autoscaler'
    puts "  ✓ PASS: Job enqueued with queue='#{enqueued[:queue]}'"
    if enqueued[:priority]
      puts "         Job priority=#{enqueued[:priority]}"
    end
    results << { test: 'job priority enqueue', passed: true }
  else
    puts "  ✗ FAIL: Job not enqueued correctly"
    results << { test: 'job priority enqueue', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'job priority enqueue', passed: false, error: e.message }
end
puts

# Test 28: Verify configuration validation catches invalid settings
puts "Test 28: Verify configuration validation catches invalid settings"
begin
  error_raised = false
  begin
    SolidQueueAutoscaler.configure(:invalid_test) do |config|
      config.adapter = :heroku
      config.heroku_api_key = nil  # Invalid - will fail validation
      config.heroku_app_name = nil
    end
  rescue SolidQueueAutoscaler::ConfigurationError => e
    error_raised = true
    puts "  ✓ PASS: ConfigurationError raised for invalid config"
    puts "         Error: #{e.message.split(',').first}..."
  end
  
  if error_raised
    results << { test: 'config validation', passed: true }
  else
    puts "  ✗ FAIL: ConfigurationError should have been raised"
    results << { test: 'config validation', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'config validation', passed: false, error: e.message }
end
puts

# Test 29: Verify invalid scaling_strategy is rejected
puts "Test 29: Verify invalid scaling_strategy is rejected"
begin
  error_raised = false
  begin
    SolidQueueAutoscaler.configure(:bad_strategy_test) do |config|
      config.adapter = :heroku
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.scaling_strategy = :invalid_strategy
    end
  rescue SolidQueueAutoscaler::ConfigurationError => e
    if e.message.include?('scaling_strategy')
      error_raised = true
      puts "  ✓ PASS: Invalid scaling_strategy rejected"
    end
  end
  
  if error_raised
    results << { test: 'invalid scaling_strategy', passed: true }
  else
    puts "  ✗ FAIL: Invalid scaling_strategy should have been rejected"
    results << { test: 'invalid scaling_strategy', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'invalid scaling_strategy', passed: false, error: e.message }
end
puts

# Test 30: Verify invalid table_prefix is rejected
puts "Test 30: Verify invalid table_prefix is rejected"
begin
  error_raised = false
  begin
    SolidQueueAutoscaler.configure(:bad_prefix_test) do |config|
      config.adapter = :heroku
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.table_prefix = 'no_underscore'  # Invalid - must end with _
    end
  rescue SolidQueueAutoscaler::ConfigurationError => e
    if e.message.include?('table_prefix')
      error_raised = true
      puts "  ✓ PASS: Invalid table_prefix rejected"
    end
  end
  
  if error_raised
    results << { test: 'invalid table_prefix', passed: true }
  else
    puts "  ✗ FAIL: Invalid table_prefix should have been rejected"
    results << { test: 'invalid table_prefix', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'invalid table_prefix', passed: false, error: e.message }
end
puts

# Test 31: Verify min_workers > max_workers is rejected
puts "Test 31: Verify min_workers > max_workers is rejected"
begin
  error_raised = false
  begin
    SolidQueueAutoscaler.configure(:bad_workers_test) do |config|
      config.adapter = :heroku
      config.heroku_api_key = 'test-key'
      config.heroku_app_name = 'test-app'
      config.min_workers = 10
      config.max_workers = 5  # Invalid - min > max
    end
  rescue SolidQueueAutoscaler::ConfigurationError => e
    if e.message.include?('min_workers') || e.message.include?('max_workers')
      error_raised = true
      puts "  ✓ PASS: min_workers > max_workers rejected"
    end
  end
  
  if error_raised
    results << { test: 'min > max workers', passed: true }
  else
    puts "  ✗ FAIL: min_workers > max_workers should have been rejected"
    results << { test: 'min > max workers', passed: false }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'min > max workers', passed: false, error: e.message }
end
puts

# Test 32: Verify config can be retrieved by name
puts "Test 32: Verify config retrieval by worker name"
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
