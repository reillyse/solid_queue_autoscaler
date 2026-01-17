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
