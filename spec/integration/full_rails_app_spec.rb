# frozen_string_literal: true

# Full Rails App Integration Tests
#
# These tests simulate a complete Rails application setup including:
# - config/initializers/solid_queue_autoscaler.rb
# - config/recurring.yml
# - SolidQueue queue configuration
# - Rails boot sequence
#
# This verifies the ENTIRE configuration flow works correctly.

require 'active_job'
require 'active_job/test_helper'
require 'yaml'
require 'tempfile'

# Ensure AutoscaleJob is loaded
require_relative '../../lib/solid_queue_autoscaler/autoscale_job'

RSpec.describe 'Integration: Full Rails App Configuration', :integration do
  include ActiveJob::TestHelper

  # Store original state
  before(:all) do
    @original_queue_name = SolidQueueAutoscaler::AutoscaleJob.queue_name rescue 'autoscaler'
  end

  after(:all) do
    # CRITICAL: Restore queue_name after all tests in this file
    # to prevent pollution of other test files
    if SolidQueueAutoscaler.const_defined?(:AutoscaleJob)
      SolidQueueAutoscaler::AutoscaleJob.queue_name = 'autoscaler'
    end
    SolidQueueAutoscaler.reset_configuration!
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    SolidQueueAutoscaler.reset_configuration!
    # Reset queue_name to default before each test
    SolidQueueAutoscaler::AutoscaleJob.queue_name = 'autoscaler'
  end

  after do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    SolidQueueAutoscaler.reset_configuration!
    # CRITICAL: Always restore to 'autoscaler' after each test
    SolidQueueAutoscaler::AutoscaleJob.queue_name = 'autoscaler'
  end

  # ============================================================================
  # RECURRING.YML CONFIGURATION TESTS
  # ============================================================================
  describe 'recurring.yml configuration scenarios' do
    # Simulates parsing recurring.yml and determining the queue
    def parse_recurring_yml(yaml_content)
      YAML.safe_load(yaml_content, permitted_classes: [Symbol])
    end

    def simulate_solid_queue_recurring_enqueue(task_config)
      # SolidQueue's logic for determining queue:
      # 1. Use queue from YAML if specified
      # 2. Otherwise, call job_class.queue_name
      job_class = Object.const_get(task_config['class'])
      queue = task_config['queue'] || job_class.queue_name
      
      # Enqueue with the determined queue
      job_class.set(queue: queue).perform_later
      
      {
        determined_queue: queue,
        enqueued_job: ActiveJob::Base.queue_adapter.enqueued_jobs.last
      }
    end

    context 'Scenario 1: recurring.yml WITHOUT queue specified (common case)' do
      let(:recurring_yml) do
        <<~YAML
          autoscaler:
            class: SolidQueueAutoscaler::AutoscaleJob
            schedule: every 30 seconds
        YAML
      end

      it 'uses the class default queue (autoscaler)' do
        config = parse_recurring_yml(recurring_yml)['autoscaler']
        
        result = simulate_solid_queue_recurring_enqueue(config)
        
        expect(result[:determined_queue]).to eq('autoscaler'),
          "SolidQueue would use queue '#{result[:determined_queue]}' instead of 'autoscaler'"
        expect(result[:enqueued_job][:queue]).to eq('autoscaler')
        expect(result[:enqueued_job][:queue]).not_to eq('default'),
          "CRITICAL: Job would go to 'default' queue!"
      end
    end

    context 'Scenario 2: recurring.yml WITH queue explicitly specified' do
      let(:recurring_yml) do
        <<~YAML
          autoscaler:
            class: SolidQueueAutoscaler::AutoscaleJob
            queue: autoscaler
            schedule: every 30 seconds
        YAML
      end

      it 'uses the explicit queue from YAML' do
        config = parse_recurring_yml(recurring_yml)['autoscaler']
        
        result = simulate_solid_queue_recurring_enqueue(config)
        
        expect(result[:determined_queue]).to eq('autoscaler')
        expect(result[:enqueued_job][:queue]).to eq('autoscaler')
      end
    end

    context 'Scenario 3: recurring.yml with custom queue' do
      let(:recurring_yml) do
        <<~YAML
          autoscaler:
            class: SolidQueueAutoscaler::AutoscaleJob
            queue: high_priority
            schedule: every 30 seconds
        YAML
      end

      it 'uses the custom queue from YAML' do
        config = parse_recurring_yml(recurring_yml)['autoscaler']
        
        result = simulate_solid_queue_recurring_enqueue(config)
        
        expect(result[:determined_queue]).to eq('high_priority')
        expect(result[:enqueued_job][:queue]).to eq('high_priority')
      end
    end

    context 'Scenario 4: Multiple autoscaler jobs in recurring.yml' do
      let(:recurring_yml) do
        <<~YAML
          autoscaler_worker:
            class: SolidQueueAutoscaler::AutoscaleJob
            schedule: every 30 seconds

          autoscaler_priority:
            class: SolidQueueAutoscaler::AutoscaleJob
            queue: priority_autoscaler
            schedule: every 30 seconds

          autoscaler_all:
            class: SolidQueueAutoscaler::AutoscaleJob
            schedule: every 1 minute
        YAML
      end

      it 'handles multiple job configurations correctly' do
        configs = parse_recurring_yml(recurring_yml)
        
        # Job 1: No queue specified - uses class default
        result1 = simulate_solid_queue_recurring_enqueue(configs['autoscaler_worker'])
        expect(result1[:determined_queue]).to eq('autoscaler')
        
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
        
        # Job 2: Custom queue specified
        result2 = simulate_solid_queue_recurring_enqueue(configs['autoscaler_priority'])
        expect(result2[:determined_queue]).to eq('priority_autoscaler')
        
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
        
        # Job 3: No queue specified - uses class default
        result3 = simulate_solid_queue_recurring_enqueue(configs['autoscaler_all'])
        expect(result3[:determined_queue]).to eq('autoscaler')
      end
    end
  end

  # ============================================================================
  # INITIALIZER CONFIGURATION TESTS
  # ============================================================================
  describe 'initializer configuration scenarios' do
    context 'Scenario: User sparrow_api configuration' do
      # This is the EXACT configuration from the user's sparrow_api app
      def apply_sparrow_api_config
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'worker'
          config.job_queue = 'autoscaler'
          config.queues = nil # all queues
          config.min_workers = 1
          config.max_workers = 5
          config.scale_up_queue_depth = 100
          config.scale_up_latency_seconds = 300
          config.scale_down_queue_depth = 10
          config.scale_down_latency_seconds = 30
          config.cooldown_seconds = 120
          config.enabled = true
          config.dry_run = true
          config.job_priority = 0
        end

        SolidQueueAutoscaler.configure(:priority_worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'priority_worker'
          config.queues = %w[indexing mailers notifications]
          config.min_workers = 1
          config.max_workers = 3
          config.scale_up_queue_depth = 50
          config.scale_up_latency_seconds = 60
          config.scale_down_queue_depth = 5
          config.scale_down_latency_seconds = 15
          config.cooldown_seconds = 60
          config.enabled = true
          config.dry_run = true
          config.job_queue = 'autoscaler'
          config.job_priority = 0
        end
      end

      it 'correctly configures multiple workers' do
        apply_sparrow_api_config
        
        expect(SolidQueueAutoscaler.registered_workers).to contain_exactly(:worker, :priority_worker)
        
        worker_config = SolidQueueAutoscaler.config(:worker)
        expect(worker_config.process_type).to eq('worker')
        expect(worker_config.job_queue).to eq('autoscaler')
        expect(worker_config.queues).to be_nil
        
        priority_config = SolidQueueAutoscaler.config(:priority_worker)
        expect(priority_config.process_type).to eq('priority_worker')
        expect(priority_config.job_queue).to eq('autoscaler')
        expect(priority_config.queues).to eq(%w[indexing mailers notifications])
      end

      it 'applies job settings correctly after configuration' do
        apply_sparrow_api_config
        SolidQueueAutoscaler.apply_job_settings!
        
        expect(SolidQueueAutoscaler::AutoscaleJob.queue_name).to eq('autoscaler')
      end

      it 'enqueues jobs to autoscaler queue after full setup' do
        apply_sparrow_api_config
        SolidQueueAutoscaler.apply_job_settings!
        
        SolidQueueAutoscaler::AutoscaleJob.perform_later(:worker)
        
        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(enqueued[:queue]).to eq('autoscaler'),
          "Job went to '#{enqueued[:queue]}' instead of 'autoscaler'"
      end
    end

    context 'Scenario: Single worker (default) configuration' do
      def apply_single_worker_config
        SolidQueueAutoscaler.configure do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.process_type = 'worker'
          config.min_workers = 1
          config.max_workers = 10
          config.dry_run = true
          config.enabled = true
        end
      end

      it 'uses default job_queue of autoscaler' do
        apply_single_worker_config
        
        config = SolidQueueAutoscaler.config
        expect(config.job_queue).to eq(:autoscaler)
      end

      it 'applies job settings with default queue' do
        apply_single_worker_config
        SolidQueueAutoscaler.apply_job_settings!
        
        expect(SolidQueueAutoscaler::AutoscaleJob.queue_name).to eq('autoscaler')
      end
    end

    context 'Scenario: Custom job_queue configuration' do
      def apply_custom_queue_config
        SolidQueueAutoscaler.configure do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.job_queue = :my_custom_autoscaler_queue
          config.dry_run = true
        end
      end

      it 'uses the custom queue from configuration' do
        apply_custom_queue_config
        SolidQueueAutoscaler.apply_job_settings!
        
        expect(SolidQueueAutoscaler::AutoscaleJob.queue_name).to eq('my_custom_autoscaler_queue')
        
        SolidQueueAutoscaler::AutoscaleJob.perform_later
        
        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(enqueued[:queue]).to eq('my_custom_autoscaler_queue')
      end
    end
  end

  # ============================================================================
  # FULL RAILS BOOT SEQUENCE SIMULATION
  # ============================================================================
  describe 'Full Rails boot sequence simulation' do
    # This simulates the EXACT order of operations during Rails boot:
    # 1. Zeitwerk loads job classes
    # 2. SolidQueue initializes (parses recurring.yml, captures queue_name)
    # 3. Rails initializers run (config/initializers/solid_queue_autoscaler.rb)
    # 4. Rails after_initialize callbacks run (apply_job_settings!)
    
    def simulate_rails_boot
      results = {}
      
      # Step 1: Zeitwerk loads job class
      # (simulated by reloading the file)
      SolidQueueAutoscaler.send(:remove_const, :AutoscaleJob) if SolidQueueAutoscaler.const_defined?(:AutoscaleJob)
      load File.expand_path('../../../lib/solid_queue_autoscaler/autoscale_job.rb', __FILE__)
      results[:step1_after_class_load] = SolidQueueAutoscaler::AutoscaleJob.queue_name
      
      # Step 2: SolidQueue initializes and reads queue_name
      # (this is where SolidQueue captures the queue for recurring jobs)
      results[:step2_solid_queue_sees] = SolidQueueAutoscaler::AutoscaleJob.queue_name
      
      # Step 3: Rails initializers run
      yield if block_given?
      results[:step3_after_initializer] = SolidQueueAutoscaler::AutoscaleJob.queue_name
      
      # Step 4: Rails after_initialize runs
      SolidQueueAutoscaler.apply_job_settings!
      results[:step4_after_initialize] = SolidQueueAutoscaler::AutoscaleJob.queue_name
      
      results
    end

    it 'shows queue_name at each step of Rails boot (with default config)' do
      results = simulate_rails_boot do
        # Initializer with default job_queue
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.dry_run = true
        end
      end
      
      # All steps should show 'autoscaler'
      expect(results[:step1_after_class_load]).to eq('autoscaler'),
        "Step 1 (class load): queue_name should be 'autoscaler', got '#{results[:step1_after_class_load]}'"
      expect(results[:step2_solid_queue_sees]).to eq('autoscaler'),
        "Step 2 (SolidQueue init): queue_name should be 'autoscaler', got '#{results[:step2_solid_queue_sees]}'"
      expect(results[:step3_after_initializer]).to eq('autoscaler'),
        "Step 3 (after initializer): queue_name should be 'autoscaler', got '#{results[:step3_after_initializer]}'"
      expect(results[:step4_after_initialize]).to eq('autoscaler'),
        "Step 4 (after_initialize): queue_name should be 'autoscaler', got '#{results[:step4_after_initialize]}'"
    end

    it 'shows queue_name at each step with custom job_queue config' do
      results = simulate_rails_boot do
        # Initializer with custom job_queue
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.job_queue = :my_custom_queue
          config.dry_run = true
        end
      end
      
      # Steps 1-3 should show 'autoscaler' (class default)
      # Step 4 should show 'my_custom_queue' (after apply_job_settings!)
      expect(results[:step1_after_class_load]).to eq('autoscaler')
      expect(results[:step2_solid_queue_sees]).to eq('autoscaler')
      expect(results[:step3_after_initializer]).to eq('autoscaler')
      expect(results[:step4_after_initialize]).to eq('my_custom_queue'),
        "Step 4 should update to custom queue"
    end

    it 'CRITICAL: SolidQueue sees "autoscaler" at step 2 (not "default")' do
      results = simulate_rails_boot do
        # Any configuration
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.dry_run = true
        end
      end
      
      expect(results[:step2_solid_queue_sees]).to eq('autoscaler'),
        "CRITICAL BUG: SolidQueue would see '#{results[:step2_solid_queue_sees]}' at initialization!\n" \
        "This means recurring jobs would go to the wrong queue."
      
      expect(results[:step2_solid_queue_sees]).not_to eq('default'),
        "CRITICAL BUG: SolidQueue would see 'default' queue!"
    end
  end

  # ============================================================================
  # QUEUE.YML CONFIGURATION TESTS
  # ============================================================================
  describe 'queue.yml configuration scenarios' do
    # These tests verify the recommended queue.yml configurations work

    context 'Recommended queue.yml with dedicated autoscaler queue' do
      let(:queue_yml) do
        <<~YAML
          default:
            dispatchers:
              - polling_interval: 1
                batch_size: 500
            workers:
              - queues:
                  - autoscaler
                threads: 1
              - queues:
                  - default
                  - mailers
                threads: 5
        YAML
      end

      it 'validates queue configuration includes autoscaler queue' do
        config = YAML.safe_load(queue_yml, permitted_classes: [Symbol])
        
        workers = config['default']['workers']
        queues = workers.flat_map { |w| w['queues'] }
        
        expect(queues).to include('autoscaler'),
          "queue.yml should include 'autoscaler' queue for the autoscaler job"
      end
    end
  end

  # ============================================================================
  # EDGE CASES AND ERROR SCENARIOS
  # ============================================================================
  describe 'Edge cases and error scenarios' do
    context 'when no configuration is applied' do
      it 'still uses autoscaler queue (class default)' do
        # Don't configure anything
        SolidQueueAutoscaler.reset_configuration!
        
        # Class default should still be 'autoscaler'
        expect(SolidQueueAutoscaler::AutoscaleJob.queue_name).to eq('autoscaler')
        
        SolidQueueAutoscaler::AutoscaleJob.perform_later
        
        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(enqueued[:queue]).to eq('autoscaler'),
          "Without configuration, job went to '#{enqueued[:queue]}' instead of 'autoscaler'"
      end
    end

    context 'when apply_job_settings! is called before configure' do
      it 'does not crash and maintains class default' do
        SolidQueueAutoscaler.reset_configuration!
        
        # This could happen if railtie after_initialize runs before initializer
        expect { SolidQueueAutoscaler.apply_job_settings! }.not_to raise_error
        
        # Class default should still be intact
        expect(SolidQueueAutoscaler::AutoscaleJob.queue_name).to eq('autoscaler')
      end
    end

    context 'when configuration has nil job_queue' do
      it 'falls back to :autoscaler' do
        SolidQueueAutoscaler.configure(:worker) do |config|
          config.adapter = :heroku
          config.heroku_api_key = 'test-key'
          config.heroku_app_name = 'test-app'
          config.job_queue = nil
          config.dry_run = true
        end
        
        SolidQueueAutoscaler.apply_job_settings!
        
        # Should use default :autoscaler
        expect(SolidQueueAutoscaler::AutoscaleJob.queue_name).to eq('autoscaler')
      end
    end
  end

  # ============================================================================
  # COMPREHENSIVE VERIFICATION
  # ============================================================================
  describe 'Comprehensive verification checklist' do
    it 'passes all critical checks' do
      checklist = {}
      
      # 1. Class has queue_as :autoscaler in source
      source_file = File.expand_path('../../../lib/solid_queue_autoscaler/autoscale_job.rb', __FILE__)
      source_code = File.read(source_file)
      checklist[:queue_as_in_source] = source_code.include?('queue_as :autoscaler')
      
      # 2. Fresh class load has correct queue_name
      SolidQueueAutoscaler.send(:remove_const, :AutoscaleJob) if SolidQueueAutoscaler.const_defined?(:AutoscaleJob)
      load source_file
      checklist[:fresh_load_queue] = SolidQueueAutoscaler::AutoscaleJob.queue_name == 'autoscaler'
      
      # 3. Configuration sets job_queue correctly
      SolidQueueAutoscaler.reset_configuration!
      SolidQueueAutoscaler.configure(:worker) do |config|
        config.adapter = :heroku
        config.heroku_api_key = 'test-key'
        config.heroku_app_name = 'test-app'
        config.job_queue = :autoscaler
        config.dry_run = true
      end
      checklist[:config_job_queue] = SolidQueueAutoscaler.config(:worker).job_queue == :autoscaler
      
      # 4. apply_job_settings! works
      SolidQueueAutoscaler.apply_job_settings!
      checklist[:apply_job_settings] = SolidQueueAutoscaler::AutoscaleJob.queue_name == 'autoscaler'
      
      # 5. perform_later uses correct queue
      SolidQueueAutoscaler::AutoscaleJob.perform_later
      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      checklist[:perform_later_queue] = enqueued[:queue] == 'autoscaler'
      
      # 6. Queue is NOT default
      checklist[:not_default_queue] = enqueued[:queue] != 'default'
      
      # Report
      puts "\n" + "=" * 60
      puts "COMPREHENSIVE VERIFICATION CHECKLIST"
      puts "=" * 60
      checklist.each do |check, passed|
        status = passed ? '✅ PASS' : '❌ FAIL'
        puts "#{status}: #{check}"
      end
      puts "=" * 60
      
      # Assert all checks pass
      checklist.each do |check, passed|
        expect(passed).to be(true), "Check failed: #{check}"
      end
    end
  end
end
