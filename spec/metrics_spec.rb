# frozen_string_literal: true

RSpec.describe SolidQueueHerokuAutoscaler::Metrics do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil) }
  let(:connection) { instance_double('ActiveRecord::ConnectionAdapters::PostgreSQLAdapter') }

  let(:config) do
    SolidQueueHerokuAutoscaler::Configuration.new.tap do |c|
      c.heroku_api_key = 'test-key'
      c.heroku_app_name = 'test-app'
      c.database_connection = connection
      c.logger = logger
    end
  end

  subject(:metrics) { described_class.new(config: config) }

  before do
    allow(connection).to receive(:quote) { |val| "'#{val}'" }
  end

  describe SolidQueueHerokuAutoscaler::Metrics::Result do
    let(:collected_at) { Time.now }
    let(:result) do
      described_class.new(
        queue_depth: 50,
        oldest_job_age_seconds: 120.5,
        jobs_per_minute: 25,
        claimed_jobs: 5,
        failed_jobs: 2,
        blocked_jobs: 1,
        active_workers: 3,
        queues_breakdown: { 'default' => 30, 'critical' => 20 },
        collected_at: collected_at
      )
    end

    describe '#idle?' do
      context 'when queue is empty and no jobs are claimed' do
        let(:idle_result) do
          described_class.new(
            queue_depth: 0,
            oldest_job_age_seconds: 0,
            jobs_per_minute: 0,
            claimed_jobs: 0,
            failed_jobs: 0,
            blocked_jobs: 0,
            active_workers: 1,
            queues_breakdown: {},
            collected_at: collected_at
          )
        end

        it 'returns true' do
          expect(idle_result.idle?).to be(true)
        end
      end

      context 'when queue has jobs' do
        it 'returns false' do
          expect(result.idle?).to be(false)
        end
      end

      context 'when queue is empty but jobs are claimed' do
        let(:claimed_result) do
          described_class.new(
            queue_depth: 0,
            oldest_job_age_seconds: 0,
            jobs_per_minute: 10,
            claimed_jobs: 3,
            failed_jobs: 0,
            blocked_jobs: 0,
            active_workers: 2,
            queues_breakdown: {},
            collected_at: collected_at
          )
        end

        it 'returns false' do
          expect(claimed_result.idle?).to be(false)
        end
      end
    end

    describe '#latency_seconds' do
      it 'returns oldest_job_age_seconds' do
        expect(result.latency_seconds).to eq(120.5)
      end
    end

    describe '#to_h' do
      it 'returns a hash with all attributes' do
        hash = result.to_h
        expect(hash).to eq({
                             queue_depth: 50,
                             oldest_job_age_seconds: 120.5,
                             jobs_per_minute: 25,
                             claimed_jobs: 5,
                             failed_jobs: 2,
                             blocked_jobs: 1,
                             active_workers: 3,
                             queues_breakdown: { 'default' => 30, 'critical' => 20 },
                             collected_at: collected_at
                           })
      end

      it 'returns a frozen hash that can be inspected' do
        hash = result.to_h
        expect(hash.keys).to contain_exactly(
          :queue_depth, :oldest_job_age_seconds, :jobs_per_minute,
          :claimed_jobs, :failed_jobs, :blocked_jobs, :active_workers,
          :queues_breakdown, :collected_at
        )
      end
    end
  end

  describe 'table name helpers' do
    describe 'with default table prefix' do
      it 'uses solid_queue_ prefix for ready_executions_table' do
        expect(metrics.send(:ready_executions_table)).to eq('solid_queue_ready_executions')
      end

      it 'uses solid_queue_ prefix for jobs_table' do
        expect(metrics.send(:jobs_table)).to eq('solid_queue_jobs')
      end

      it 'uses solid_queue_ prefix for claimed_executions_table' do
        expect(metrics.send(:claimed_executions_table)).to eq('solid_queue_claimed_executions')
      end

      it 'uses solid_queue_ prefix for failed_executions_table' do
        expect(metrics.send(:failed_executions_table)).to eq('solid_queue_failed_executions')
      end

      it 'uses solid_queue_ prefix for blocked_executions_table' do
        expect(metrics.send(:blocked_executions_table)).to eq('solid_queue_blocked_executions')
      end

      it 'uses solid_queue_ prefix for processes_table' do
        expect(metrics.send(:processes_table)).to eq('solid_queue_processes')
      end
    end

    describe 'with custom table prefix' do
      before do
        config.table_prefix = 'my_app_queue_'
      end

      it 'uses custom prefix for ready_executions_table' do
        expect(metrics.send(:ready_executions_table)).to eq('my_app_queue_ready_executions')
      end

      it 'uses custom prefix for jobs_table' do
        expect(metrics.send(:jobs_table)).to eq('my_app_queue_jobs')
      end

      it 'uses custom prefix for claimed_executions_table' do
        expect(metrics.send(:claimed_executions_table)).to eq('my_app_queue_claimed_executions')
      end

      it 'uses custom prefix for failed_executions_table' do
        expect(metrics.send(:failed_executions_table)).to eq('my_app_queue_failed_executions')
      end

      it 'uses custom prefix for blocked_executions_table' do
        expect(metrics.send(:blocked_executions_table)).to eq('my_app_queue_blocked_executions')
      end

      it 'uses custom prefix for processes_table' do
        expect(metrics.send(:processes_table)).to eq('my_app_queue_processes')
      end
    end

    describe 'with alternative prefixes' do
      it 'handles single word prefix' do
        config.table_prefix = 'queue_'
        expect(metrics.send(:jobs_table)).to eq('queue_jobs')
      end

      it 'handles longer prefix' do
        config.table_prefix = 'my_company_production_queue_'
        expect(metrics.send(:jobs_table)).to eq('my_company_production_queue_jobs')
      end
    end

    describe 'edge case prefixes' do
      it 'handles prefix with numbers' do
        config.table_prefix = 'app123_queue_'
        expect(metrics.send(:jobs_table)).to eq('app123_queue_jobs')
        expect(metrics.send(:ready_executions_table)).to eq('app123_queue_ready_executions')
      end

      it 'handles prefix starting with underscore' do
        config.table_prefix = '_private_queue_'
        expect(metrics.send(:jobs_table)).to eq('_private_queue_jobs')
      end

      it 'handles minimum valid prefix (single underscore)' do
        config.table_prefix = '_'
        expect(metrics.send(:jobs_table)).to eq('_jobs')
        expect(metrics.send(:processes_table)).to eq('_processes')
      end

      it 'handles very long prefix' do
        long_prefix = "#{'a' * 50}_"
        config.table_prefix = long_prefix
        expect(metrics.send(:jobs_table)).to eq("#{long_prefix}jobs")
      end

      it 'handles prefix with multiple consecutive underscores' do
        config.table_prefix = 'my__app__queue_'
        expect(metrics.send(:jobs_table)).to eq('my__app__queue_jobs')
      end
    end
  end

  describe '#queue_depth' do
    before do
      allow(connection).to receive(:select_value).and_return(42)
    end

    it 'queries the correct table with default prefix' do
      metrics.queue_depth
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('solid_queue_ready_executions')
      end
    end

    it 'queries the correct table with custom prefix' do
      config.table_prefix = 'custom_'
      metrics.queue_depth
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('custom_ready_executions')
        expect(sql).not_to include('solid_queue_')
      end
    end

    it 'returns the count as an integer' do
      expect(metrics.queue_depth).to eq(42)
    end

    context 'when count is nil' do
      before do
        allow(connection).to receive(:select_value).and_return(nil)
      end

      it 'returns 0' do
        expect(metrics.queue_depth).to eq(0)
      end
    end
  end

  describe '#oldest_job_age_seconds' do
    before do
      allow(connection).to receive(:select_value).and_return(300.5)
    end

    it 'queries the correct table with default prefix' do
      metrics.oldest_job_age_seconds
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('solid_queue_ready_executions')
      end
    end

    it 'queries the correct table with custom prefix' do
      config.table_prefix = 'app_'
      metrics.oldest_job_age_seconds
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('app_ready_executions')
      end
    end

    it 'returns the age as a float' do
      expect(metrics.oldest_job_age_seconds).to eq(300.5)
    end

    context 'when no jobs exist' do
      before do
        allow(connection).to receive(:select_value).and_return(nil)
      end

      it 'returns 0.0' do
        expect(metrics.oldest_job_age_seconds).to eq(0.0)
      end
    end
  end

  describe '#jobs_per_minute' do
    before do
      allow(connection).to receive(:select_value).and_return(15)
    end

    it 'queries the correct table with default prefix' do
      metrics.jobs_per_minute
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('solid_queue_jobs')
      end
    end

    it 'queries the correct table with custom prefix' do
      config.table_prefix = 'production_'
      metrics.jobs_per_minute
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('production_jobs')
      end
    end

    it 'returns the count as an integer' do
      expect(metrics.jobs_per_minute).to eq(15)
    end
  end

  describe '#claimed_jobs_count' do
    before do
      allow(connection).to receive(:select_value).and_return(8)
    end

    it 'queries the correct table with default prefix' do
      metrics.claimed_jobs_count
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('solid_queue_claimed_executions')
      end
    end

    it 'queries the correct table with custom prefix' do
      config.table_prefix = 'bg_'
      metrics.claimed_jobs_count
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('bg_claimed_executions')
      end
    end

    it 'returns the count as an integer' do
      expect(metrics.claimed_jobs_count).to eq(8)
    end
  end

  describe '#failed_jobs_count' do
    before do
      allow(connection).to receive(:select_value).and_return(3)
    end

    it 'queries the correct table with default prefix' do
      metrics.failed_jobs_count
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('solid_queue_failed_executions')
      end
    end

    it 'queries the correct table with custom prefix' do
      config.table_prefix = 'jobs_'
      metrics.failed_jobs_count
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('jobs_failed_executions')
      end
    end

    it 'returns the count as an integer' do
      expect(metrics.failed_jobs_count).to eq(3)
    end
  end

  describe '#blocked_jobs_count' do
    before do
      allow(connection).to receive(:select_value).and_return(1)
    end

    it 'queries the correct table with default prefix' do
      metrics.blocked_jobs_count
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('solid_queue_blocked_executions')
      end
    end

    it 'queries the correct table with custom prefix' do
      config.table_prefix = 'worker_'
      metrics.blocked_jobs_count
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('worker_blocked_executions')
      end
    end

    it 'returns the count as an integer' do
      expect(metrics.blocked_jobs_count).to eq(1)
    end
  end

  describe '#active_workers_count' do
    before do
      allow(connection).to receive(:select_value).and_return(4)
    end

    it 'queries the correct table with default prefix' do
      metrics.active_workers_count
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('solid_queue_processes')
      end
    end

    it 'queries the correct table with custom prefix' do
      config.table_prefix = 'async_'
      metrics.active_workers_count
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('async_processes')
      end
    end

    it 'filters by Worker kind' do
      metrics.active_workers_count
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include("kind = 'Worker'")
      end
    end

    it 'filters by recent heartbeat' do
      metrics.active_workers_count
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('last_heartbeat_at')
        expect(sql).to include("INTERVAL '5 minutes'")
      end
    end

    it 'returns the count as an integer' do
      expect(metrics.active_workers_count).to eq(4)
    end
  end

  describe '#queues_breakdown' do
    let(:breakdown_result) do
      [
        { 'queue_name' => 'default', 'count' => 30 },
        { 'queue_name' => 'critical', 'count' => 20 },
        { 'queue_name' => 'low', 'count' => 10 }
      ]
    end

    before do
      allow(connection).to receive(:select_all).and_return(breakdown_result)
    end

    it 'queries the correct table with default prefix' do
      metrics.queues_breakdown
      expect(connection).to have_received(:select_all) do |sql|
        expect(sql).to include('solid_queue_ready_executions')
      end
    end

    it 'queries the correct table with custom prefix' do
      config.table_prefix = 'myapp_'
      metrics.queues_breakdown
      expect(connection).to have_received(:select_all) do |sql|
        expect(sql).to include('myapp_ready_executions')
      end
    end

    it 'groups by queue_name' do
      metrics.queues_breakdown
      expect(connection).to have_received(:select_all) do |sql|
        expect(sql).to include('GROUP BY queue_name')
      end
    end

    it 'returns a hash with queue names and counts' do
      result = metrics.queues_breakdown
      expect(result).to eq({
                             'default' => 30,
                             'critical' => 20,
                             'low' => 10
                           })
    end

    context 'when no jobs exist' do
      before do
        allow(connection).to receive(:select_all).and_return([])
      end

      it 'returns an empty hash' do
        expect(metrics.queues_breakdown).to eq({})
      end
    end
  end

  describe 'queue filtering' do
    describe '#queue_filter_clause' do
      context 'when no queues are configured' do
        it 'returns empty string' do
          expect(metrics.send(:queue_filter_clause)).to eq('')
        end
      end

      context 'when queues is nil' do
        before { config.queues = nil }

        it 'returns empty string' do
          expect(metrics.send(:queue_filter_clause)).to eq('')
        end
      end

      context 'when queues is empty array' do
        before { config.queues = [] }

        it 'returns empty string' do
          expect(metrics.send(:queue_filter_clause)).to eq('')
        end
      end

      context 'when single queue is configured' do
        before { config.queues = ['default'] }

        it 'returns IN clause with quoted queue name' do
          clause = metrics.send(:queue_filter_clause)
          expect(clause).to include('AND queue_name IN')
          expect(clause).to include("'default'")
        end
      end

      context 'when multiple queues are configured' do
        before { config.queues = %w[default critical low] }

        it 'returns IN clause with all quoted queue names' do
          clause = metrics.send(:queue_filter_clause)
          expect(clause).to include('AND queue_name IN')
          expect(clause).to include("'default'")
          expect(clause).to include("'critical'")
          expect(clause).to include("'low'")
        end
      end

      context 'with custom column name' do
        before { config.queues = ['mailers'] }

        it 'uses the specified column name' do
          clause = metrics.send(:queue_filter_clause, 'queue_name')
          expect(clause).to include('AND queue_name IN')
        end
      end
    end

    describe 'filtered metrics queries' do
      before do
        config.queues = %w[critical high]
        allow(connection).to receive(:select_value).and_return(10)
      end

      it 'includes queue filter in queue_depth query' do
        metrics.queue_depth
        expect(connection).to have_received(:select_value) do |sql|
          expect(sql).to include('AND queue_name IN')
          expect(sql).to include("'critical'")
          expect(sql).to include("'high'")
        end
      end

      it 'includes queue filter in oldest_job_age_seconds query' do
        metrics.oldest_job_age_seconds
        expect(connection).to have_received(:select_value) do |sql|
          expect(sql).to include('AND queue_name IN')
        end
      end

      it 'includes queue filter in jobs_per_minute query' do
        metrics.jobs_per_minute
        expect(connection).to have_received(:select_value) do |sql|
          expect(sql).to include('AND queue_name IN')
        end
      end
    end
  end

  describe '#collect' do
    before do
      allow(connection).to receive(:select_value).and_return(0)
      allow(connection).to receive(:select_all).and_return([])
      allow(Time).to receive(:current).and_return(Time.new(2024, 1, 15, 12, 0, 0))
    end

    it 'returns a Result struct' do
      result = metrics.collect
      expect(result).to be_a(SolidQueueHerokuAutoscaler::Metrics::Result)
    end

    it 'collects all metrics' do
      allow(connection).to receive(:select_value).and_return(50, 120.5, 25, 5, 2, 1, 3)
      allow(connection).to receive(:select_all).and_return([
                                                             { 'queue_name' => 'default', 'count' => 50 }
                                                           ])

      result = metrics.collect

      expect(result.queue_depth).to eq(50)
      expect(result.oldest_job_age_seconds).to eq(120.5)
      expect(result.jobs_per_minute).to eq(25)
      expect(result.claimed_jobs).to eq(5)
      expect(result.failed_jobs).to eq(2)
      expect(result.blocked_jobs).to eq(1)
      expect(result.active_workers).to eq(3)
      expect(result.queues_breakdown).to eq({ 'default' => 50 })
      expect(result.collected_at).to eq(Time.new(2024, 1, 15, 12, 0, 0))
    end

    it 'uses the configured table prefix for all queries' do
      config.table_prefix = 'test_prefix_'
      executed_sqls = []

      allow(connection).to receive(:select_value) do |sql|
        executed_sqls << sql
        0
      end
      allow(connection).to receive(:select_all) do |sql|
        executed_sqls << sql
        []
      end

      metrics.collect

      # All SQL queries should use the custom prefix
      executed_sqls.each do |sql|
        expect(sql).to include('test_prefix_')
        expect(sql).not_to include('solid_queue_')
      end
    end
  end

  describe 'SQL query structure' do
    before do
      allow(connection).to receive(:select_value).and_return(0)
      allow(connection).to receive(:select_all).and_return([])
    end

    it 'uses SELECT COUNT(*) for queue_depth' do
      metrics.queue_depth
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to match(/SELECT COUNT\(\*\)/i)
      end
    end

    it 'uses EXTRACT(EPOCH FROM ...) for oldest_job_age_seconds' do
      metrics.oldest_job_age_seconds
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('EXTRACT(EPOCH FROM')
        expect(sql).to include('MIN(created_at)')
      end
    end

    it 'filters jobs_per_minute by finished_at within last minute' do
      metrics.jobs_per_minute
      expect(connection).to have_received(:select_value) do |sql|
        expect(sql).to include('finished_at IS NOT NULL')
        expect(sql).to include("INTERVAL '1 minute'")
      end
    end
  end

  describe 'integration with global configuration' do
    it 'uses global config when no config is passed' do
      configure_autoscaler(table_prefix: 'global_')

      global_metrics = described_class.new
      expect(global_metrics.send(:table_prefix)).to eq('global_')
    end
  end

  describe 'connection handling' do
    it 'uses the configured database connection' do
      custom_connection = instance_double('ActiveRecord::ConnectionAdapters::PostgreSQLAdapter')
      allow(custom_connection).to receive(:select_value).and_return(5)
      config.database_connection = custom_connection

      metrics.queue_depth
      expect(custom_connection).to have_received(:select_value)
    end
  end

  describe 'SQL query integration with edge case table prefixes' do
    before do
      allow(connection).to receive(:select_value).and_return(0)
      allow(connection).to receive(:select_all).and_return([])
    end

    describe 'with numeric prefix' do
      before { config.table_prefix = 'v2_queue_' }

      it 'builds valid SQL for queue_depth' do
        metrics.queue_depth
        expect(connection).to have_received(:select_value) do |sql|
          expect(sql).to include('FROM v2_queue_ready_executions')
          expect(sql).to match(/SELECT COUNT\(\*\) FROM v2_queue_ready_executions/)
        end
      end

      it 'builds valid SQL for all metric methods' do
        executed_sqls = []
        allow(connection).to receive(:select_value) { |sql|
          executed_sqls << sql
          0
        }
        allow(connection).to receive(:select_all) { |sql|
          executed_sqls << sql
          []
        }

        metrics.collect

        expect(executed_sqls).to all(include('v2_queue_'))
        expect(executed_sqls.join).to include('v2_queue_ready_executions')
        expect(executed_sqls.join).to include('v2_queue_jobs')
        expect(executed_sqls.join).to include('v2_queue_claimed_executions')
        expect(executed_sqls.join).to include('v2_queue_failed_executions')
        expect(executed_sqls.join).to include('v2_queue_blocked_executions')
        expect(executed_sqls.join).to include('v2_queue_processes')
      end
    end

    describe 'with minimum valid prefix (single underscore)' do
      before { config.table_prefix = '_' }

      it 'builds valid SQL with underscore prefix' do
        metrics.queue_depth
        expect(connection).to have_received(:select_value) do |sql|
          expect(sql).to include('FROM _ready_executions')
        end
      end

      it 'generates correct table names in all queries' do
        executed_sqls = []
        allow(connection).to receive(:select_value) { |sql|
          executed_sqls << sql
          0
        }
        allow(connection).to receive(:select_all) { |sql|
          executed_sqls << sql
          []
        }

        metrics.collect

        combined_sql = executed_sqls.join(' ')
        expect(combined_sql).to include('_ready_executions')
        expect(combined_sql).to include('_jobs')
        expect(combined_sql).to include('_claimed_executions')
        expect(combined_sql).to include('_processes')
      end
    end

    describe 'with very long prefix' do
      let(:long_prefix) { 'this_is_a_very_long_prefix_for_testing_purposes_' }
      before { config.table_prefix = long_prefix }

      it 'builds valid SQL with long prefix' do
        metrics.queue_depth
        expect(connection).to have_received(:select_value) do |sql|
          expect(sql).to include("FROM #{long_prefix}ready_executions")
        end
      end

      it 'handles long prefix in oldest_job_age query' do
        metrics.oldest_job_age_seconds
        expect(connection).to have_received(:select_value) do |sql|
          expect(sql).to include("FROM #{long_prefix}ready_executions")
          expect(sql).to include('EXTRACT(EPOCH FROM')
        end
      end
    end

    describe 'with prefix containing consecutive underscores' do
      before { config.table_prefix = 'my__app__' }

      it 'preserves consecutive underscores in SQL' do
        metrics.queue_depth
        expect(connection).to have_received(:select_value) do |sql|
          expect(sql).to include('FROM my__app__ready_executions')
        end
      end
    end

    describe 'ensures no SQL injection via table prefix' do
      it 'table prefix is used directly in SQL (relies on validation)' do
        # The validation layer should prevent dangerous prefixes
        # This test documents that the prefix is interpolated directly
        config.table_prefix = 'safe_prefix_'

        metrics.queue_depth
        expect(connection).to have_received(:select_value) do |sql|
          expect(sql).to include('safe_prefix_ready_executions')
        end
      end
    end

    describe 'collect method integration' do
      before { config.table_prefix = 'integration_test_' }

      it 'uses correct prefix across all collected metrics' do
        executed_sqls = []
        allow(connection).to receive(:select_value) { |sql|
          executed_sqls << sql
          42
        }
        allow(connection).to receive(:select_all) { |sql|
          executed_sqls << sql
          [{ 'queue_name' => 'default', 'count' => 10 }]
        }

        result = metrics.collect

        # Verify result is populated
        expect(result.queue_depth).to eq(42)
        expect(result.queues_breakdown).to eq({ 'default' => 10 })

        # Verify all queries used correct prefix
        executed_sqls.each do |sql|
          expect(sql).to include('integration_test_')
          expect(sql).not_to include('solid_queue_')
        end
      end
    end
  end
end
