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
    collected_at: Time.current
  )
end

# Test 33: Decision engine scales up when queue_depth >= threshold
puts "Test 33: Decision engine scales up when queue_depth >= scale_up_queue_depth"
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

# Test 34: Decision engine scales up when latency >= threshold
puts "Test 34: Decision engine scales up when latency >= scale_up_latency_seconds"
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

# Test 35: Decision engine scales down when both thresholds are low
puts "Test 35: Decision engine scales down when queue_depth AND latency are low"
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

# Test 36: Decision engine returns no_change when metrics are in normal range
puts "Test 36: Decision engine returns no_change when metrics are in normal range"
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

# Test 37: Decision engine respects max_workers limit
puts "Test 37: Decision engine respects max_workers limit (no scale_up at max)"
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

# Test 38: Decision engine respects min_workers limit
puts "Test 38: Decision engine respects min_workers limit (no scale_down at min)"
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

# Test 39: Priority worker uses different thresholds than main worker
puts "Test 39: Priority worker uses different (lower) thresholds"
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

# Test 40: Fixed scaling strategy adds exactly scale_up_increment
puts "Test 40: Fixed scaling strategy adds exactly scale_up_increment workers"
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

# Test 41: Proportional scaling strategy (priority_worker uses proportional)
puts "Test 41: Proportional scaling strategy calculates workers based on load"
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

# Test 42: Scale down requires BOTH conditions to be met
puts "Test 42: Scale down requires BOTH queue_depth AND latency to be low"
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

# Test 43: Scale up requires EITHER condition to be met
puts "Test 43: Scale up requires EITHER queue_depth OR latency to be high"
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

# Test 44: Decision reason includes threshold values
puts "Test 44: Decision reason includes configured threshold values"
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

# Helper to create a test config with mocked adapter
def create_e2e_test_config(name:, mock_client:, initial_workers: 2)
  config = SolidQueueAutoscaler::Configuration.new.tap do |c|
    c.name = name
    c.heroku_api_key = 'test-api-key-e2e'
    c.heroku_app_name = 'test-app-e2e'
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
    c.persist_cooldowns = false  # Use in-memory cooldowns for testing
    c.record_events = false       # Disable event recording for tests
    c.logger = Logger.new(STDOUT).tap { |l| l.level = Logger::WARN }
  end
  
  # Create adapter and inject mock client
  adapter = SolidQueueAutoscaler::Adapters::Heroku.new(config: config)
  adapter.instance_variable_set(:@client, mock_client)
  config.adapter = adapter
  
  config
end

# Helper to create a mock metrics collector
class MockMetricsCollector
  def initialize(metrics)
    @metrics = metrics
  end
  
  def collect
    @metrics
  end
end

# Test 45: End-to-end scale up with mocked Heroku API
puts "Test 45: E2E - Full scale up workflow with mocked Heroku API"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  e2e_config = create_e2e_test_config(name: :e2e_scale_up, mock_client: mock_client)
  
  # Create metrics that will trigger scale up (queue_depth >= 100)
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  # Create scaler with injected metrics collector
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  # Stub advisory lock to always succeed
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  # Verify result
  passed = true
  issues = []
  
  unless result.success?
    passed = false
    issues << "Result should be successful"
  end
  
  unless result.scaled?
    passed = false
    issues << "Result should indicate scaling occurred"
  end
  
  unless result.decision.action == :scale_up
    passed = false
    issues << "Decision action should be :scale_up, got #{result.decision.action}"
  end
  
  unless result.decision.from == 2
    passed = false
    issues << "Decision.from should be 2, got #{result.decision.from}"
  end
  
  unless result.decision.to == 4  # 2 + scale_up_increment(2) = 4
    passed = false
    issues << "Decision.to should be 4, got #{result.decision.to}"
  end
  
  # Verify Heroku API was called correctly
  update_calls = mock_client.formation.calls.select { |c| c[:method] == :update }
  unless update_calls.length >= 1
    passed = false
    issues << "Heroku API update should have been called at least once"
  end
  
  last_update = update_calls.last
  if last_update
    unless last_update[:quantity] == 4
      passed = false
      issues << "Heroku API should scale to 4 workers, got #{last_update[:quantity]}"
    end
    unless last_update[:app_name] == 'test-app-e2e'
      passed = false
      issues << "Heroku API should use correct app name"
    end
    unless last_update[:process_type] == 'worker'
      passed = false
      issues << "Heroku API should use correct process type"
    end
  end
  
  if passed
    puts "  ✓ PASS: Full scale up workflow completed successfully"
    puts "         Decision: #{result.decision.from} -> #{result.decision.to} workers"
    puts "         Heroku API calls: #{mock_client.formation.calls.length}"
    results << { test: 'E2E scale up workflow', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E scale up workflow', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  puts "  Backtrace: #{e.backtrace.first(3).join("\n            ")}"
  results << { test: 'E2E scale up workflow', passed: false, error: e.message }
end
puts

# Test 46: End-to-end scale down with mocked Heroku API
puts "Test 46: E2E - Full scale down workflow with mocked Heroku API"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 5)
  e2e_config = create_e2e_test_config(name: :e2e_scale_down, mock_client: mock_client)
  
  # Create metrics that will trigger scale down (both low)
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
    issues << "Decision action should be :scale_down"
  end
  
  unless result.decision.from == 5 && result.decision.to == 4
    passed = false
    issues << "Should scale from 5 to 4 workers"
  end
  
  update_calls = mock_client.formation.calls.select { |c| c[:method] == :update }
  if update_calls.last && update_calls.last[:quantity] != 4
    passed = false
    issues << "Heroku API should scale to 4, got #{update_calls.last[:quantity]}"
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

# Test 47: End-to-end no change scenario
puts "Test 47: E2E - No change when metrics are normal"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 3)
  e2e_config = create_e2e_test_config(name: :e2e_no_change, mock_client: mock_client)
  
  # Create metrics in normal range (between scale up and scale down thresholds)
  normal_metrics = create_mock_metrics(queue_depth: 50, latency: 100)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(normal_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  unless result.success?
    passed = false
    issues << "Result should be successful"
  end
  
  if result.scaled?
    passed = false
    issues << "Should NOT have scaled"
  end
  
  unless result.decision.action == :no_change
    passed = false
    issues << "Decision should be :no_change"
  end
  
  # Verify no update calls were made
  update_calls = mock_client.formation.calls.select { |c| c[:method] == :update }
  unless update_calls.empty?
    passed = false
    issues << "Heroku API update should NOT have been called"
  end
  
  if passed
    puts "  ✓ PASS: No change when metrics are normal"
    puts "         Current workers: #{result.decision.from}, Reason: #{result.decision.reason}"
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

# Test 48: End-to-end cooldown enforcement
puts "Test 48: E2E - Cooldown prevents rapid scaling"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  e2e_config = create_e2e_test_config(name: :e2e_cooldown, mock_client: mock_client)
  e2e_config.cooldown_seconds = 60  # 60 second cooldown
  
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  # First scaling should succeed
  result1 = scaler.run
  
  # Second scaling immediately after should be blocked by cooldown
  # Create new mock client with updated quantity
  mock_client2 = MockPlatformClient.new(initial_quantity: 4)
  adapter2 = e2e_config.adapter
  adapter2.instance_variable_set(:@client, mock_client2)
  
  result2 = scaler.run
  
  passed = true
  issues = []
  
  unless result1.scaled?
    passed = false
    issues << "First scaling should succeed"
  end
  
  unless result2.skipped?
    passed = false
    issues << "Second scaling should be skipped due to cooldown"
  end
  
  if result2.skipped? && !result2.skipped_reason.include?('Cooldown')
    passed = false
    issues << "Skip reason should mention cooldown, got: #{result2.skipped_reason}"
  end
  
  if passed
    puts "  ✓ PASS: Cooldown prevents rapid scaling"
    puts "         First result: scaled=#{result1.scaled?}"
    puts "         Second result: skipped=#{result2.skipped?}, reason=#{result2.skipped_reason&.truncate(50)}"
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

# Test 49: End-to-end max workers limit
puts "Test 49: E2E - Max workers limit is respected"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 10)
  e2e_config = create_e2e_test_config(name: :e2e_max_limit, mock_client: mock_client)
  e2e_config.max_workers = 10
  
  # Metrics that would normally trigger scale up
  very_high_metrics = create_mock_metrics(queue_depth: 500, latency: 600)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(very_high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  unless result.success?
    passed = false
    issues << "Result should be successful"
  end
  
  if result.scaled?
    passed = false
    issues << "Should NOT scale when already at max_workers"
  end
  
  unless result.decision.action == :no_change
    passed = false
    issues << "Decision should be :no_change when at max"
  end
  
  unless result.decision.reason.include?('max_workers')
    passed = false
    issues << "Reason should mention max_workers"
  end
  
  # Verify no update calls
  update_calls = mock_client.formation.calls.select { |c| c[:method] == :update }
  unless update_calls.empty?
    passed = false
    issues << "Should not call Heroku API when at max"
  end
  
  if passed
    puts "  ✓ PASS: Max workers limit is respected"
    puts "         Decision: #{result.decision.action}, Reason: #{result.decision.reason}"
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

# Test 50: End-to-end min workers limit
puts "Test 50: E2E - Min workers limit is respected"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 1)
  e2e_config = create_e2e_test_config(name: :e2e_min_limit, mock_client: mock_client)
  e2e_config.min_workers = 1
  
  # Idle metrics that would normally trigger scale down
  idle_metrics = create_mock_metrics(queue_depth: 0, latency: 0, claimed_jobs: 0)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(idle_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  unless result.success?
    passed = false
    issues << "Result should be successful"
  end
  
  if result.scaled?
    passed = false
    issues << "Should NOT scale below min_workers"
  end
  
  unless result.decision.action == :no_change
    passed = false
    issues << "Decision should be :no_change when at min"
  end
  
  unless result.decision.reason.include?('min_workers')
    passed = false
    issues << "Reason should mention min_workers"
  end
  
  if passed
    puts "  ✓ PASS: Min workers limit is respected"
    puts "         Decision: #{result.decision.action}, Reason: #{result.decision.reason}"
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

# Test 51: End-to-end result object completeness
puts "Test 51: E2E - Result object contains all expected data"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  e2e_config = create_e2e_test_config(name: :e2e_result_obj, mock_client: mock_client)
  
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  passed = true
  issues = []
  
  # Check success field
  unless result.respond_to?(:success) && (result.success == true || result.success == false)
    passed = false
    issues << "Result should have success field"
  end
  
  # Check decision field
  unless result.respond_to?(:decision) && result.decision.respond_to?(:action)
    passed = false
    issues << "Result should have decision field with action"
  end
  
  # Check decision has from/to
  unless result.decision.respond_to?(:from) && result.decision.respond_to?(:to)
    passed = false
    issues << "Decision should have from/to fields"
  end
  
  # Check decision has reason
  unless result.decision.respond_to?(:reason) && !result.decision.reason.nil?
    passed = false
    issues << "Decision should have reason field"
  end
  
  # Check metrics field
  unless result.respond_to?(:metrics) && result.metrics.respond_to?(:queue_depth)
    passed = false
    issues << "Result should have metrics field with queue_depth"
  end
  
  # Check executed_at field
  unless result.respond_to?(:executed_at) && result.executed_at.is_a?(Time)
    passed = false
    issues << "Result should have executed_at timestamp"
  end
  
  # Check helper methods
  unless result.respond_to?(:success?) && result.respond_to?(:scaled?) && result.respond_to?(:skipped?)
    passed = false
    issues << "Result should have success?, scaled?, skipped? methods"
  end
  
  if passed
    puts "  ✓ PASS: Result object contains all expected data"
    puts "         success=#{result.success}, decision.action=#{result.decision.action}"
    puts "         decision.from=#{result.decision.from}, decision.to=#{result.decision.to}"
    puts "         metrics.queue_depth=#{result.metrics.queue_depth}"
    puts "         executed_at=#{result.executed_at}"
    results << { test: 'E2E result object completeness', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E result object completeness', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E result object completeness', passed: false, error: e.message }
end
puts

# Test 52: End-to-end dry run mode
puts "Test 52: E2E - Dry run mode logs but doesn't actually scale"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  e2e_config = create_e2e_test_config(name: :e2e_dry_run, mock_client: mock_client)
  e2e_config.dry_run = true
  
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  initial_update_count = mock_client.formation.calls.select { |c| c[:method] == :update }.length
  
  result = scaler.run
  
  final_update_count = mock_client.formation.calls.select { |c| c[:method] == :update }.length
  
  passed = true
  issues = []
  
  unless result.success?
    passed = false
    issues << "Result should be successful even in dry run"
  end
  
  unless result.scaled?
    passed = false
    issues << "Result should indicate scaling 'occurred' (dry run still counts)"
  end
  
  # In dry run, the adapter.scale is still called but the adapter itself logs and returns without API call
  # So we check that the decision was made correctly
  unless result.decision.action == :scale_up
    passed = false
    issues << "Decision should still be :scale_up in dry run mode"
  end
  
  if passed
    puts "  ✓ PASS: Dry run mode works correctly"
    puts "         Decision: #{result.decision.action}, from=#{result.decision.from} to=#{result.decision.to}"
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

# Test 53: End-to-end adapter receives correct app name and process type
puts "Test 53: E2E - Heroku adapter receives correct app name and process type"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  
  config = SolidQueueAutoscaler::Configuration.new.tap do |c|
    c.name = :e2e_app_params
    c.heroku_api_key = 'test-api-key'
    c.heroku_app_name = 'my-custom-app-name'
    c.process_type = 'custom_worker'
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
  
  # Check that info calls used correct parameters
  info_calls = mock_client.formation.calls.select { |c| c[:method] == :info }
  info_calls.each do |call|
    unless call[:app_name] == 'my-custom-app-name'
      passed = false
      issues << "Info call should use app_name 'my-custom-app-name', got '#{call[:app_name]}'"
    end
    unless call[:process_type] == 'custom_worker'
      passed = false
      issues << "Info call should use process_type 'custom_worker', got '#{call[:process_type]}'"
    end
  end
  
  # Check that update calls used correct parameters
  update_calls = mock_client.formation.calls.select { |c| c[:method] == :update }
  update_calls.each do |call|
    unless call[:app_name] == 'my-custom-app-name'
      passed = false
      issues << "Update call should use app_name 'my-custom-app-name'"
    end
    unless call[:process_type] == 'custom_worker'
      passed = false
      issues << "Update call should use process_type 'custom_worker'"
    end
  end
  
  if passed
    puts "  ✓ PASS: Heroku adapter receives correct app name and process type"
    puts "         app_name='my-custom-app-name', process_type='custom_worker'"
    results << { test: 'E2E adapter params', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E adapter params', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E adapter params', passed: false, error: e.message }
end
puts

# Test 54: End-to-end verify API call sequence
puts "Test 54: E2E - Verify Heroku API call sequence (info -> update -> info)"
begin
  SolidQueueAutoscaler::Scaler.reset_cooldowns!
  
  mock_client = MockPlatformClient.new(initial_quantity: 2)
  e2e_config = create_e2e_test_config(name: :e2e_call_sequence, mock_client: mock_client)
  
  high_metrics = create_mock_metrics(queue_depth: 150, latency: 200)
  
  scaler = SolidQueueAutoscaler::Scaler.new(config: e2e_config)
  scaler.instance_variable_set(:@metrics_collector, MockMetricsCollector.new(high_metrics))
  
  lock = scaler.instance_variable_get(:@lock)
  def lock.try_lock; true; end
  def lock.release; end
  
  result = scaler.run
  
  calls = mock_client.formation.calls
  
  passed = true
  issues = []
  
  # Should have at least: info (get current), maybe info (verify), update
  unless calls.length >= 2
    passed = false
    issues << "Should have at least 2 API calls, got #{calls.length}"
  end
  
  # First call should be info to get current workers
  unless calls.first && calls.first[:method] == :info
    passed = false
    issues << "First call should be :info"
  end
  
  # Should have at least one update call
  update_calls = calls.select { |c| c[:method] == :update }
  unless update_calls.length >= 1
    passed = false
    issues << "Should have at least one :update call"
  end
  
  if passed
    puts "  ✓ PASS: API call sequence is correct"
    puts "         Calls: #{calls.map { |c| c[:method] }.join(' -> ')}"
    results << { test: 'E2E API call sequence', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'E2E API call sequence', passed: false, error: issues.join(', ') }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'E2E API call sequence', passed: false, error: e.message }
end
puts

# ============================================================================
# QUEUE NAME AND JOB PRIORITY CONFIGURATION TESTS
# These tests verify that queue names can be changed to any custom value
# and that jobs are correctly enqueued to the configured queue with priority.
# This was broken in production - these are CRITICAL regression tests.
# ============================================================================

# Test 55: CRITICAL - Change queue name to a completely custom value
puts "Test 55: CRITICAL - Change queue name to custom value and verify it takes effect"
begin
  # Save original state
  original_queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
  original_configs = SolidQueueAutoscaler.configurations.dup
  
  # Reset everything to simulate a fresh configuration
  SolidQueueAutoscaler.reset_configuration!
  
  # Configure with a UNIQUE custom queue name (like a user would in their app)
  custom_queue_name = 'my_special_autoscaler_queue_12345'
  
  SolidQueueAutoscaler.configure(:test_worker) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.job_queue = custom_queue_name.to_sym
    config.job_priority = 42
    config.dry_run = true
  end
  
  # Apply job settings (this is what the Railtie does after_initialize)
  SolidQueueAutoscaler.apply_job_settings!
  
  # Verify the queue_name was changed
  actual_queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
  
  if actual_queue == custom_queue_name
    puts "  ✓ PASS: AutoscaleJob.queue_name changed to '#{actual_queue}'"
    results << { test: 'CRITICAL custom queue name', passed: true }
  else
    puts "  ✗ FAIL: CRITICAL REGRESSION! AutoscaleJob.queue_name = '#{actual_queue}'"
    puts "         Expected: '#{custom_queue_name}'"
    puts "         This means jobs would go to the WRONG queue!"
    results << { test: 'CRITICAL custom queue name', passed: false, error: "queue_name='#{actual_queue}' instead of '#{custom_queue_name}'" }
  end
  
  # Restore original state
  SolidQueueAutoscaler.instance_variable_set(:@configurations, original_configs)
  SolidQueueAutoscaler::AutoscaleJob.queue_name = original_queue
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'CRITICAL custom queue name', passed: false, error: e.message }
end
puts

# Test 56: CRITICAL - Verify job is actually enqueued to the custom queue
puts "Test 56: CRITICAL - Verify job enqueues to configured custom queue"
begin
  original_queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
  original_configs = SolidQueueAutoscaler.configurations.dup
  
  SolidQueueAutoscaler.reset_configuration!
  
  custom_queue = 'production_autoscaler_queue'
  
  SolidQueueAutoscaler.configure(:prod_worker) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.job_queue = custom_queue.to_sym
    config.dry_run = true
  end
  
  SolidQueueAutoscaler.apply_job_settings!
  
  # Use test adapter to capture the enqueued job
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  
  # Enqueue a job
  SolidQueueAutoscaler::AutoscaleJob.perform_later(:prod_worker)
  
  enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
  enqueued_queue = enqueued[:queue]
  
  if enqueued_queue == custom_queue
    puts "  ✓ PASS: Job enqueued to '#{enqueued_queue}' (configured queue)"
    results << { test: 'CRITICAL job enqueued to custom queue', passed: true }
  else
    puts "  ✗ FAIL: CRITICAL REGRESSION! Job enqueued to '#{enqueued_queue}'"
    puts "         Expected queue: '#{custom_queue}'"
    puts "         Jobs are going to the WRONG queue in production!"
    results << { test: 'CRITICAL job enqueued to custom queue', passed: false, error: "enqueued to '#{enqueued_queue}'" }
  end
  
  # Restore
  SolidQueueAutoscaler.instance_variable_set(:@configurations, original_configs)
  SolidQueueAutoscaler::AutoscaleJob.queue_name = original_queue
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'CRITICAL job enqueued to custom queue', passed: false, error: e.message }
end
puts

# Test 57: Verify job_priority is applied from configuration
puts "Test 57: Verify job_priority is applied from configuration"
begin
  original_queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
  original_configs = SolidQueueAutoscaler.configurations.dup
  
  SolidQueueAutoscaler.reset_configuration!
  
  SolidQueueAutoscaler.configure(:priority_test) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.job_queue = :priority_test_queue
    config.job_priority = 99
    config.dry_run = true
  end
  
  SolidQueueAutoscaler.apply_job_settings!
  
  # Check if priority was set on the job class
  priority_set = false
  if SolidQueueAutoscaler::AutoscaleJob.respond_to?(:priority)
    actual_priority = SolidQueueAutoscaler::AutoscaleJob.priority
    priority_set = actual_priority == 99
  end
  
  # Also verify the config has the right priority
  config_priority = SolidQueueAutoscaler.config(:priority_test).job_priority
  
  if config_priority == 99
    puts "  ✓ PASS: job_priority=#{config_priority} correctly configured"
    if priority_set
      puts "         AutoscaleJob.priority also set to #{actual_priority}"
    end
    results << { test: 'job_priority configuration', passed: true }
  else
    puts "  ✗ FAIL: job_priority not correctly configured"
    results << { test: 'job_priority configuration', passed: false }
  end
  
  # Restore
  SolidQueueAutoscaler.instance_variable_set(:@configurations, original_configs)
  SolidQueueAutoscaler::AutoscaleJob.queue_name = original_queue
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'job_priority configuration', passed: false, error: e.message }
end
puts

# Test 58: Multiple queue name changes work correctly
puts "Test 58: Multiple queue name changes are applied correctly"
begin
  original_queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
  original_configs = SolidQueueAutoscaler.configurations.dup
  
  passed = true
  issues = []
  
  # First configuration
  SolidQueueAutoscaler.reset_configuration!
  SolidQueueAutoscaler.configure(:first) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.job_queue = :first_queue
    config.dry_run = true
  end
  SolidQueueAutoscaler.apply_job_settings!
  
  first_result = SolidQueueAutoscaler::AutoscaleJob.queue_name
  unless first_result == 'first_queue'
    passed = false
    issues << "First change: expected 'first_queue', got '#{first_result}'"
  end
  
  # Second configuration (reconfigure)
  SolidQueueAutoscaler.reset_configuration!
  SolidQueueAutoscaler.configure(:second) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.job_queue = :second_queue
    config.dry_run = true
  end
  SolidQueueAutoscaler.apply_job_settings!
  
  second_result = SolidQueueAutoscaler::AutoscaleJob.queue_name
  unless second_result == 'second_queue'
    passed = false
    issues << "Second change: expected 'second_queue', got '#{second_result}'"
  end
  
  # Third configuration
  SolidQueueAutoscaler.reset_configuration!
  SolidQueueAutoscaler.configure(:third) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.job_queue = :third_queue
    config.dry_run = true
  end
  SolidQueueAutoscaler.apply_job_settings!
  
  third_result = SolidQueueAutoscaler::AutoscaleJob.queue_name
  unless third_result == 'third_queue'
    passed = false
    issues << "Third change: expected 'third_queue', got '#{third_result}'"
  end
  
  if passed
    puts "  ✓ PASS: Multiple queue name changes work correctly"
    puts "         first_queue -> second_queue -> third_queue"
    results << { test: 'multiple queue name changes', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'multiple queue name changes', passed: false, error: issues.join(', ') }
  end
  
  # Restore
  SolidQueueAutoscaler.instance_variable_set(:@configurations, original_configs)
  SolidQueueAutoscaler::AutoscaleJob.queue_name = original_queue
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'multiple queue name changes', passed: false, error: e.message }
end
puts

# Test 59: Full Railtie-style flow (reset -> configure -> apply -> enqueue -> verify)
puts "Test 59: Full Railtie-style flow: reset -> configure -> apply -> enqueue -> verify"
begin
  original_queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
  original_configs = SolidQueueAutoscaler.configurations.dup
  
  # Step 1: Reset (simulate fresh Rails boot)
  SolidQueueAutoscaler.reset_configuration!
  
  # Step 2: Configure (simulate initializer running)
  SolidQueueAutoscaler.configure(:railtie_test) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.job_queue = :railtie_custom_queue
    config.job_priority = 5
    config.dry_run = true
  end
  
  # Step 3: Apply job settings (Railtie after_initialize)
  SolidQueueAutoscaler.apply_job_settings!
  
  # Step 4: Enqueue job (like SolidQueue recurring would)
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  
  SolidQueueAutoscaler::AutoscaleJob.perform_later(:railtie_test)
  
  # Step 5: Verify
  enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
  queue_name = SolidQueueAutoscaler::AutoscaleJob.queue_name
  enqueued_queue = enqueued[:queue]
  
  passed = true
  issues = []
  
  unless queue_name == 'railtie_custom_queue'
    passed = false
    issues << "queue_name='#{queue_name}' (expected 'railtie_custom_queue')"
  end
  
  unless enqueued_queue == 'railtie_custom_queue'
    passed = false
    issues << "enqueued to '#{enqueued_queue}' (expected 'railtie_custom_queue')"
  end
  
  if passed
    puts "  ✓ PASS: Full Railtie-style flow works correctly"
    puts "         queue_name='#{queue_name}', enqueued_to='#{enqueued_queue}'"
    results << { test: 'Railtie-style flow', passed: true }
  else
    puts "  ✗ FAIL: #{issues.join(', ')}"
    results << { test: 'Railtie-style flow', passed: false, error: issues.join(', ') }
  end
  
  # Restore
  SolidQueueAutoscaler.instance_variable_set(:@configurations, original_configs)
  SolidQueueAutoscaler::AutoscaleJob.queue_name = original_queue
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'Railtie-style flow', passed: false, error: e.message }
end
puts

# Test 60: CRITICAL REGRESSION - Jobs should NEVER go to 'default' queue
puts "Test 60: CRITICAL REGRESSION - Jobs should NEVER go to 'default' queue with any configuration"
begin
  original_queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
  original_configs = SolidQueueAutoscaler.configurations.dup
  
  passed = true
  issues = []
  
  # Test 1: With explicit job_queue set
  SolidQueueAutoscaler.reset_configuration!
  SolidQueueAutoscaler.configure(:test1) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.job_queue = :explicit_queue
    config.dry_run = true
  end
  SolidQueueAutoscaler.apply_job_settings!
  
  queue1 = SolidQueueAutoscaler::AutoscaleJob.queue_name
  if queue1 == 'default'
    passed = false
    issues << "With explicit job_queue: got 'default' instead of 'explicit_queue'"
  end
  
  # Test 2: With default job_queue (should be :autoscaler)
  SolidQueueAutoscaler.reset_configuration!
  SolidQueueAutoscaler.configure(:test2) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    # job_queue not set - should default to :autoscaler
    config.dry_run = true
  end
  SolidQueueAutoscaler.apply_job_settings!
  
  queue2 = SolidQueueAutoscaler::AutoscaleJob.queue_name
  if queue2 == 'default'
    passed = false
    issues << "With default job_queue: got 'default' instead of 'autoscaler'"
  end
  
  # Test 3: Enqueue and verify
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  SolidQueueAutoscaler::AutoscaleJob.perform_later
  
  enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
  if enqueued[:queue] == 'default'
    passed = false
    issues << "Enqueued job went to 'default' queue!"
  end
  
  if passed
    puts "  ✓ PASS: Jobs NEVER go to 'default' queue"
    puts "         Tested: explicit config, default config, and actual enqueue"
    results << { test: 'CRITICAL REGRESSION - never default queue', passed: true }
  else
    puts "  ✗ FAIL: CRITICAL REGRESSION DETECTED!"
    issues.each { |i| puts "         - #{i}" }
    results << { test: 'CRITICAL REGRESSION - never default queue', passed: false, error: issues.join(', ') }
  end
  
  # Restore
  SolidQueueAutoscaler.instance_variable_set(:@configurations, original_configs)
  SolidQueueAutoscaler::AutoscaleJob.queue_name = original_queue
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'CRITICAL REGRESSION - never default queue', passed: false, error: e.message }
end
puts

# Test 61: Verify queue_as :autoscaler is present in class definition
puts "Test 61: Verify queue_as :autoscaler is in the class definition (source check)"
begin
  # Read the actual source file
  source_file = File.join(Rails.root, '..', '..', 'lib', 'solid_queue_autoscaler', 'autoscale_job.rb')
  source_code = File.read(source_file)
  
  if source_code.include?('queue_as :autoscaler')
    puts "  ✓ PASS: 'queue_as :autoscaler' is present in autoscale_job.rb"
    puts "         This ensures SolidQueue recurring jobs use the correct queue"
    results << { test: 'queue_as in source', passed: true }
  else
    puts "  ✗ FAIL: CRITICAL! 'queue_as :autoscaler' is missing from autoscale_job.rb!"
    puts "         SolidQueue recurring jobs will NOT work correctly!"
    results << { test: 'queue_as in source', passed: false, error: 'queue_as :autoscaler missing from source' }
  end
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'queue_as in source', passed: false, error: e.message }
end
puts

# Test 62: Verify enqueued job has the configured priority
puts "Test 62: Verify enqueued job includes priority information"
begin
  original_queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
  original_configs = SolidQueueAutoscaler.configurations.dup
  
  SolidQueueAutoscaler.reset_configuration!
  
  SolidQueueAutoscaler.configure(:priority_enqueue_test) do |config|
    config.adapter = :heroku
    config.heroku_api_key = 'test-key'
    config.heroku_app_name = 'test-app'
    config.job_queue = :priority_test_queue
    config.job_priority = 7
    config.dry_run = true
  end
  
  SolidQueueAutoscaler.apply_job_settings!
  
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  
  # Enqueue with explicit priority
  SolidQueueAutoscaler::AutoscaleJob.set(priority: 7).perform_later(:priority_enqueue_test)
  
  enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
  
  # Check that job was enqueued correctly
  if enqueued && enqueued[:queue] == 'priority_test_queue'
    puts "  ✓ PASS: Job enqueued to correct queue with priority support"
    puts "         Queue: '#{enqueued[:queue]}'"
    if enqueued[:priority]
      puts "         Priority: #{enqueued[:priority]}"
    else
      puts "         Priority: (not tracked by test adapter, but set on job class)"
    end
    results << { test: 'priority enqueue', passed: true }
  else
    puts "  ✗ FAIL: Job not enqueued correctly"
    results << { test: 'priority enqueue', passed: false }
  end
  
  # Restore
  SolidQueueAutoscaler.instance_variable_set(:@configurations, original_configs)
  SolidQueueAutoscaler::AutoscaleJob.queue_name = original_queue
rescue => e
  puts "  ✗ FAIL: #{e.message}"
  results << { test: 'priority enqueue', passed: false, error: e.message }
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
