# frozen_string_literal: true

# Integration tests that simulate a real Rails app boot sequence
# to verify AutoscaleJob queue behavior matches what SolidQueue expects.
#
# This tests the EXACT behavior SolidQueue uses to determine the queue:
# 1. Load the job class
# 2. Call job_class.queue_name to get the queue
# 3. If no queue specified in recurring.yml, use the class default
#
# IMPORTANT: These tests simulate the Rails boot sequence where:
# 1. Job classes are loaded during app initialization
# 2. SolidQueue reads queue_name BEFORE Rails after_initialize hooks run
# 3. The queue_as declaration must be static (not a block) for SolidQueue

require 'active_job'
require 'active_job/test_helper'

RSpec.describe 'Integration: Dummy Rails App Queue Behavior', :integration do
  include ActiveJob::TestHelper

  # Store the original class to restore after all tests
  before(:all) do
    @original_queue_name = SolidQueueAutoscaler::AutoscaleJob.queue_name rescue 'autoscaler'
  end

  after(:all) do
    # Ensure the class is properly restored after all integration tests
    # Always reload the class to get a fresh state with queue_as :autoscaler
    if SolidQueueAutoscaler.const_defined?(:AutoscaleJob)
      SolidQueueAutoscaler.send(:remove_const, :AutoscaleJob)
    end
    load File.expand_path('../../../lib/solid_queue_autoscaler/autoscale_job.rb', __FILE__)
  end

  # After each test, restore the queue_name to 'autoscaler'
  after do
    if SolidQueueAutoscaler.const_defined?(:AutoscaleJob)
      SolidQueueAutoscaler::AutoscaleJob.queue_name = 'autoscaler'
    end
  end

  # Simulate a fresh Rails boot by unloading and reloading the job class
  def simulate_fresh_rails_boot
    # This simulates what happens during Rails boot:
    # 1. Ruby loads the class file
    # 2. The `queue_as :autoscaler` line executes
    # 3. queue_name is set to 'autoscaler'
    
    # Force reload of the class by removing and re-requiring
    # In a real Rails app, this happens during Zeitwerk loading
    SolidQueueAutoscaler.send(:remove_const, :AutoscaleJob) if SolidQueueAutoscaler.const_defined?(:AutoscaleJob)
    
    # Re-require the file (simulates Zeitwerk loading the class)
    load File.expand_path('../../../lib/solid_queue_autoscaler/autoscale_job.rb', __FILE__)
    
    yield
  ensure
    # Always restore queue_name to 'autoscaler' after test to avoid polluting other tests
    if SolidQueueAutoscaler.const_defined?(:AutoscaleJob)
      SolidQueueAutoscaler::AutoscaleJob.queue_name = 'autoscaler'
    end
  end

  describe 'SolidQueue queue determination simulation' do
    # This tests exactly what SolidQueue does when it parses recurring.yml
    # and needs to determine which queue to use for a job class.
    
    context 'when SolidQueue loads the job class (simulating recurring.yml parsing)' do
      it 'queue_name returns "autoscaler" IMMEDIATELY after class is loaded (not "default")' do
        simulate_fresh_rails_boot do
          # CRITICAL: This is what SolidQueue does when recurring.yml doesn't specify queue:
          # It calls job_class.queue_name to get the default queue
          queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
          
          expect(queue).to eq('autoscaler'),
            "FAILURE: SolidQueue would see queue='#{queue}' instead of 'autoscaler'!\n" \
            "This means jobs would go to the '#{queue}' queue, not 'autoscaler'."
          
          expect(queue).not_to eq('default'),
            "CRITICAL BUG: queue_name returned 'default'!\n" \
            "SolidQueue recurring jobs would go to 'default' queue instead of 'autoscaler'."
        end
      end
      
      it 'queue_name is "autoscaler" BEFORE any configuration is applied' do
        simulate_fresh_rails_boot do
          # Reset all configuration to simulate fresh Rails boot
          SolidQueueAutoscaler.reset_configuration!
          
          # BEFORE any configure block runs, queue_name should already be 'autoscaler'
          # because queue_as :autoscaler is in the class definition
          queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
          
          expect(queue).to eq('autoscaler'),
            "FAILURE: Before configuration, queue_name='#{queue}' instead of 'autoscaler'.\n" \
            "The queue_as :autoscaler declaration is not being applied."
        end
      end
      
      it 'queue_name remains "autoscaler" AFTER configuration is applied' do
        simulate_fresh_rails_boot do
          # Reset and configure (simulates initializer running)
          SolidQueueAutoscaler.reset_configuration!
          SolidQueueAutoscaler.configure(:worker) do |config|
            config.adapter = :heroku
            config.heroku_api_key = 'test-key'
            config.heroku_app_name = 'test-app'
            config.job_queue = :autoscaler
          end
          SolidQueueAutoscaler.apply_job_settings!
          
          queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
          
          expect(queue).to eq('autoscaler'),
            "FAILURE: After configuration, queue_name='#{queue}' instead of 'autoscaler'."
        end
      end
    end
    
    context 'simulating SolidQueue recurring job enqueue' do
      # This simulates EXACTLY what SolidQueue does when enqueueing a recurring job:
      # 1. Parse recurring.yml
      # 2. Get the job class
      # 3. If queue: not specified in YAML, use job_class.queue_name
      # 4. Enqueue the job with that queue
      
      before do
        ActiveJob::Base.queue_adapter = :test
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      end
      
      after do
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      end
      
      def simulate_solid_queue_enqueue(job_class, queue_from_yaml: nil)
        # This is what SolidQueue's recurring runner does:
        # 1. Get the queue from YAML, or fall back to job class default
        queue = queue_from_yaml || job_class.queue_name
        
        # 2. Enqueue the job with that queue
        job_class.set(queue: queue).perform_later
        
        # 3. Return the enqueued job info
        ActiveJob::Base.queue_adapter.enqueued_jobs.last
      end
      
      it 'enqueues to "autoscaler" when recurring.yml does NOT specify queue:' do
        simulate_fresh_rails_boot do
          # Simulate: recurring.yml has NO queue: specified
          #   autoscaler:
          #     class: SolidQueueAutoscaler::AutoscaleJob
          #     schedule: every 30 seconds
          
          enqueued = simulate_solid_queue_enqueue(
            SolidQueueAutoscaler::AutoscaleJob,
            queue_from_yaml: nil  # No queue in YAML
          )
          
          expect(enqueued[:queue]).to eq('autoscaler'),
            "FAILURE: Job enqueued to '#{enqueued[:queue]}' instead of 'autoscaler'.\n" \
            "SolidQueue would put this job in the wrong queue!"
          
          expect(enqueued[:queue]).not_to eq('default'),
            "CRITICAL BUG: Job enqueued to 'default' queue!"
        end
      end
      
      it 'enqueues to specified queue when recurring.yml DOES specify queue:' do
        simulate_fresh_rails_boot do
          # Simulate: recurring.yml HAS queue: specified
          #   autoscaler:
          #     class: SolidQueueAutoscaler::AutoscaleJob
          #     queue: my_custom_queue
          #     schedule: every 30 seconds
          
          enqueued = simulate_solid_queue_enqueue(
            SolidQueueAutoscaler::AutoscaleJob,
            queue_from_yaml: 'my_custom_queue'  # Explicit queue in YAML
          )
          
          expect(enqueued[:queue]).to eq('my_custom_queue'),
            "FAILURE: Job enqueued to '#{enqueued[:queue]}' instead of 'my_custom_queue'."
        end
      end
      
      it 'uses class default queue when enqueuing without set(queue:)' do
        simulate_fresh_rails_boot do
          # Standard perform_later without any queue override
          SolidQueueAutoscaler::AutoscaleJob.perform_later
          
          enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
          
          expect(enqueued[:queue]).to eq('autoscaler'),
            "FAILURE: Direct perform_later went to '#{enqueued[:queue]}' instead of 'autoscaler'."
        end
      end
    end
    
    context 'Rails boot sequence simulation' do
      # This tests the EXACT order of operations during Rails boot:
      # 1. Zeitwerk loads job classes (queue_as is evaluated)
      # 2. SolidQueue initializes and parses recurring.yml
      # 3. SolidQueue captures queue_name from job classes
      # 4. Rails after_initialize runs (our apply_job_settings!)
      #
      # The critical issue: Step 3 happens BEFORE step 4!
      # So queue_as must be STATIC, not dynamic.
      
      it 'queue_as :autoscaler is evaluated during class load (step 1)' do
        simulate_fresh_rails_boot do
          # Immediately after class load, queue_name should be set
          expect(SolidQueueAutoscaler::AutoscaleJob.queue_name).to eq('autoscaler'),
            "queue_as :autoscaler was not evaluated during class load!"
        end
      end
      
      it 'queue_name is available before after_initialize (step 3 before step 4)' do
        simulate_fresh_rails_boot do
          # Before any configuration/after_initialize
          SolidQueueAutoscaler.reset_configuration!
          
          # This is what SolidQueue sees during its initialization
          queue_before_after_initialize = SolidQueueAutoscaler::AutoscaleJob.queue_name
          
          expect(queue_before_after_initialize).to eq('autoscaler'),
            "CRITICAL: Before after_initialize, queue_name='#{queue_before_after_initialize}'.\n" \
            "SolidQueue would capture this value and use it for recurring jobs!"
        end
      end
      
      it 'apply_job_settings! can override the queue (step 4)' do
        simulate_fresh_rails_boot do
          SolidQueueAutoscaler.reset_configuration!
          SolidQueueAutoscaler.configure(:worker) do |config|
            config.adapter = :heroku
            config.heroku_api_key = 'test-key'
            config.heroku_app_name = 'test-app'
            config.job_queue = :custom_queue_from_config
          end
          
          # This runs in after_initialize
          SolidQueueAutoscaler.apply_job_settings!
          
          expect(SolidQueueAutoscaler::AutoscaleJob.queue_name).to eq('custom_queue_from_config'),
            "apply_job_settings! did not update queue_name from config!"
        end
      end
    end
  end
  
  describe 'Regression: jobs should NEVER go to default queue' do
    before do
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end
    
    after do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end
    
    it 'CRITICAL: fresh class load results in "autoscaler" queue, not "default"' do
      simulate_fresh_rails_boot do
        queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
        
        expect(queue).to eq('autoscaler'),
          "REGRESSION DETECTED: AutoscaleJob.queue_name='#{queue}' after fresh load!\n" \
          "Expected 'autoscaler'. This would cause SolidQueue recurring jobs to go to '#{queue}'."
          
        expect(queue).not_to eq('default'),
          "CRITICAL REGRESSION: Jobs would go to 'default' queue!"
      end
    end
    
    it 'CRITICAL: perform_later goes to "autoscaler" queue without any configuration' do
      simulate_fresh_rails_boot do
        # No configuration at all - just a fresh class load
        SolidQueueAutoscaler.reset_configuration!
        
        SolidQueueAutoscaler::AutoscaleJob.perform_later
        
        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        
        expect(enqueued[:queue]).to eq('autoscaler'),
          "REGRESSION: perform_later went to '#{enqueued[:queue]}' without config!"
          
        expect(enqueued[:queue]).not_to eq('default'),
          "CRITICAL REGRESSION: Jobs go to 'default' without configuration!"
      end
    end
    
    it 'CRITICAL: verify queue_as :autoscaler is present in the class definition' do
      # Read the actual source file and verify queue_as :autoscaler is present
      source_file = File.expand_path('../../../lib/solid_queue_autoscaler/autoscale_job.rb', __FILE__)
      source_code = File.read(source_file)
      
      expect(source_code).to include('queue_as :autoscaler'),
        "CRITICAL: The line 'queue_as :autoscaler' is missing from autoscale_job.rb!\n" \
        "This MUST be present for SolidQueue recurring jobs to work correctly."
    end
  end
  
  describe 'User configuration scenario (matches sparrow_api)' do
    # This tests the EXACT configuration the user has in their sparrow_api app
    
    before do
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end
    
    after do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      SolidQueueAutoscaler.reset_configuration!
    end
    
    it 'matches user config: worker with job_queue = "autoscaler"' do
      simulate_fresh_rails_boot do
        SolidQueueAutoscaler.reset_configuration!
        
        # User's exact configuration from sparrow_api
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'worker'
          config.job_queue = 'autoscaler'  # User's config
          config.job_priority = 0
        end
        
        SolidQueueAutoscaler.configure(:priority_worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'priority_worker'
          config.job_queue = 'autoscaler'  # User's config
          config.job_priority = 0
        end
        
        SolidQueueAutoscaler.apply_job_settings!
        
        # Verify queue_name is correct
        expect(SolidQueueAutoscaler::AutoscaleJob.queue_name).to eq('autoscaler'),
          "With user's config, queue_name='#{SolidQueueAutoscaler::AutoscaleJob.queue_name}'"
        
        # Verify perform_later goes to correct queue
        SolidQueueAutoscaler::AutoscaleJob.perform_later(:worker)
        
        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(enqueued[:queue]).to eq('autoscaler'),
          "With user's config, job went to '#{enqueued[:queue]}' instead of 'autoscaler'!"
      end
    end
  end
  
  describe 'Debug: ActiveJob queue_as behavior' do
    # These tests help debug exactly how ActiveJob's queue_as works
    
    it 'shows what queue_name returns for AutoscaleJob' do
      queue = SolidQueueAutoscaler::AutoscaleJob.queue_name
      puts "\n=== DEBUG: AutoscaleJob.queue_name = '#{queue}' ==="
      
      # Also check the instance level
      job = SolidQueueAutoscaler::AutoscaleJob.new
      instance_queue = job.queue_name
      puts "=== DEBUG: AutoscaleJob.new.queue_name = '#{instance_queue}' ==="
      
      expect(queue).to eq('autoscaler')
      expect(instance_queue).to eq('autoscaler')
    end
    
    it 'shows the queue_name_delimiter if set' do
      delimiter = ActiveJob::Base.queue_name_delimiter rescue '/'
      puts "\n=== DEBUG: queue_name_delimiter = '#{delimiter}' ==="
      
      # Just informational, no assertion needed
    end
  end
end
