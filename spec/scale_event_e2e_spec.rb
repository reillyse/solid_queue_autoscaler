# frozen_string_literal: true

# End-to-end tests for ScaleEvent recording via the Scaler.
# These tests verify that events are actually recorded when scaling occurs.

RSpec.describe 'ScaleEvent E2E Recording', type: :integration do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil) }
  let(:connection) do
    double('connection').tap do |conn|
      allow(conn).to receive(:quote_table_name) { |name| name }
    end
  end

  let(:adapter) do
    instance_double(
      SolidQueueAutoscaler::Adapters::Heroku,
      current_workers: 2,
      scale: 3,
      name: 'Heroku'
    )
  end

  let(:config) do
    SolidQueueAutoscaler::Configuration.new.tap do |c|
      c.heroku_api_key = 'test-api-key'
      c.heroku_app_name = 'test-app'
      c.process_type = 'worker'
      c.min_workers = 1
      c.max_workers = 10
      c.scale_up_queue_depth = 100
      c.scale_up_latency_seconds = 300
      c.scale_up_increment = 1
      c.scale_down_queue_depth = 10
      c.scale_down_latency_seconds = 30
      c.scale_down_decrement = 1
      c.cooldown_seconds = 0 # Disable cooldown for tests
      c.dry_run = false
      c.enabled = true
      c.logger = logger
      c.adapter = adapter
      c.record_events = true
      c.database_connection = connection
    end
  end

  let(:lock) { instance_double(SolidQueueAutoscaler::AdvisoryLock) }
  let(:metrics_collector) { instance_double(SolidQueueAutoscaler::Metrics) }
  let(:decision_engine) { instance_double(SolidQueueAutoscaler::DecisionEngine) }

  let(:recorded_events) { [] }

  before do
    allow(SolidQueueAutoscaler::AdvisoryLock).to receive(:new).and_return(lock)
    allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)
    allow(SolidQueueAutoscaler::DecisionEngine).to receive(:new).and_return(decision_engine)
    allow(lock).to receive(:try_lock).and_return(true)
    allow(lock).to receive(:release)
    allow(lock).to receive(:with_lock).and_yield

    # Mock connection methods
    allow(connection).to receive(:table_exists?).with('solid_queue_autoscaler_events').and_return(true)
    allow(connection).to receive(:table_exists?).with('solid_queue_autoscaler_state').and_return(false) # Disable persistent cooldowns in tests
    allow(connection).to receive(:quote) { |v| v.nil? ? 'NULL' : "'#{v}'" }

    # Capture INSERT statements to track recorded events
    allow(connection).to receive(:execute) do |sql|
      if sql.include?('INSERT INTO solid_queue_autoscaler_events')
        # Parse the INSERT to extract event data
        event_data = parse_insert_sql(sql)
        recorded_events << event_data
        double('result', first: { 'id' => recorded_events.size })
      else
        double('result', first: nil)
      end
    end

    SolidQueueAutoscaler::Scaler.reset_cooldowns!
  end

  def parse_insert_sql(sql)
    # Simple parser to extract VALUES from INSERT statement
    values_match = sql.match(/VALUES\s*\((.*)\)/m)
    return {} unless values_match

    values = values_match[1]
    # Extract worker_name (first value) and action (second value)
    parts = values.split(',').map(&:strip)

    {
      worker_name: parts[0]&.gsub(/^'|'$/, ''),
      action: parts[1]&.gsub(/^'|'$/, ''),
      from_workers: parts[2]&.gsub(/^'|'$/, ''),
      to_workers: parts[3]&.gsub(/^'|'$/, ''),
      reason: parts[4]&.gsub(/^'|'$/, '')
    }
  end

  describe 'event recording when scaling up' do
    let(:high_queue_metrics) do
      SolidQueueAutoscaler::Metrics::Result.new(
        queue_depth: 150,
        oldest_job_age_seconds: 400.0,
        jobs_per_minute: 50,
        claimed_jobs: 10,
        failed_jobs: 0,
        blocked_jobs: 0,
        active_workers: 2,
        queues_breakdown: { 'default' => 150 },
        collected_at: Time.current
      )
    end

    let(:scale_up_decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_up,
        from: 2,
        to: 3,
        reason: 'queue_depth=150 >= 100'
      )
    end

    before do
      allow(metrics_collector).to receive(:collect).and_return(high_queue_metrics)
      allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
      allow(adapter).to receive(:current_workers).and_return(2)
      allow(adapter).to receive(:scale).and_return(3)
    end

    it 'records a scale_up event when scaling up' do
      scaler = SolidQueueAutoscaler::Scaler.new(config: config)
      result = scaler.run

      expect(result.scaled?).to be(true)
      expect(recorded_events.size).to eq(1)
      expect(recorded_events.first[:action]).to eq('scale_up')
      expect(recorded_events.first[:from_workers]).to eq('2')
      expect(recorded_events.first[:to_workers]).to eq('3')
    end

    it 'records the worker name in the event' do
      config.name = :critical_worker
      scaler = SolidQueueAutoscaler::Scaler.new(config: config)
      scaler.run

      expect(recorded_events.first[:worker_name]).to eq('critical_worker')
    end
  end

  describe 'event recording when scaling down' do
    let(:low_queue_metrics) do
      SolidQueueAutoscaler::Metrics::Result.new(
        queue_depth: 5,
        oldest_job_age_seconds: 10.0,
        jobs_per_minute: 200,
        claimed_jobs: 1,
        failed_jobs: 0,
        blocked_jobs: 0,
        active_workers: 5,
        queues_breakdown: { 'default' => 5 },
        collected_at: Time.current
      )
    end

    let(:scale_down_decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_down,
        from: 5,
        to: 4,
        reason: 'queue_depth=5 <= 10'
      )
    end

    before do
      allow(metrics_collector).to receive(:collect).and_return(low_queue_metrics)
      allow(decision_engine).to receive(:decide).and_return(scale_down_decision)
      allow(adapter).to receive(:current_workers).and_return(5)
      allow(adapter).to receive(:scale).and_return(4)
    end

    it 'records a scale_down event when scaling down' do
      scaler = SolidQueueAutoscaler::Scaler.new(config: config)
      result = scaler.run

      expect(result.scaled?).to be(true)
      expect(recorded_events.size).to eq(1)
      expect(recorded_events.first[:action]).to eq('scale_down')
      expect(recorded_events.first[:from_workers]).to eq('5')
      expect(recorded_events.first[:to_workers]).to eq('4')
    end
  end

  describe 'event recording when skipped' do
    before do
      config.enabled = false
    end

    it 'records a skipped event' do
      scaler = SolidQueueAutoscaler::Scaler.new(config: config)
      result = scaler.run

      expect(result.skipped?).to be(true)
      expect(recorded_events.size).to eq(1)
      expect(recorded_events.first[:action]).to eq('skipped')
      expect(recorded_events.first[:reason]).to include('disabled')
    end
  end

  describe 'event recording when error occurs' do
    before do
      config.enabled = true
      allow(metrics_collector).to receive(:collect).and_raise(StandardError.new('Database connection failed'))
    end

    it 'records an error event' do
      scaler = SolidQueueAutoscaler::Scaler.new(config: config)
      result = scaler.run

      expect(result.success?).to be(false)
      expect(recorded_events.size).to eq(1)
      expect(recorded_events.first[:action]).to eq('error')
      expect(recorded_events.first[:reason]).to include('Database connection failed')
    end
  end

  describe 'event recording when record_events is disabled' do
    let(:normal_metrics) do
      SolidQueueAutoscaler::Metrics::Result.new(
        queue_depth: 150,
        oldest_job_age_seconds: 400.0,
        jobs_per_minute: 50,
        claimed_jobs: 10,
        failed_jobs: 0,
        blocked_jobs: 0,
        active_workers: 2,
        queues_breakdown: { 'default' => 150 },
        collected_at: Time.current
      )
    end

    let(:scale_up_decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_up,
        from: 2,
        to: 3,
        reason: 'queue_depth high'
      )
    end

    before do
      config.record_events = false
      allow(metrics_collector).to receive(:collect).and_return(normal_metrics)
      allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
      allow(adapter).to receive(:current_workers).and_return(2)
      allow(adapter).to receive(:scale).and_return(3)
    end

    it 'does NOT record events when record_events is false' do
      scaler = SolidQueueAutoscaler::Scaler.new(config: config)
      result = scaler.run

      expect(result.scaled?).to be(true)
      expect(recorded_events).to be_empty
    end
  end

  describe 'event recording when table does not exist' do
    let(:normal_metrics) do
      SolidQueueAutoscaler::Metrics::Result.new(
        queue_depth: 150,
        oldest_job_age_seconds: 400.0,
        jobs_per_minute: 50,
        claimed_jobs: 10,
        failed_jobs: 0,
        blocked_jobs: 0,
        active_workers: 2,
        queues_breakdown: { 'default' => 150 },
        collected_at: Time.current
      )
    end

    let(:scale_up_decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_up,
        from: 2,
        to: 3,
        reason: 'queue_depth high'
      )
    end

    before do
      allow(connection).to receive(:table_exists?).with('solid_queue_autoscaler_events').and_return(false)
      allow(connection).to receive(:table_exists?).with('solid_queue_autoscaler_state').and_return(false)
      allow(metrics_collector).to receive(:collect).and_return(normal_metrics)
      allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
      allow(adapter).to receive(:current_workers).and_return(2)
      allow(adapter).to receive(:scale).and_return(3)
    end

    it 'does NOT record events when table does not exist' do
      scaler = SolidQueueAutoscaler::Scaler.new(config: config)
      result = scaler.run

      expect(result.scaled?).to be(true)
      expect(recorded_events).to be_empty
    end

    it 'does not raise an error when table does not exist' do
      scaler = SolidQueueAutoscaler::Scaler.new(config: config)

      expect { scaler.run }.not_to raise_error
    end
  end

  describe 'no_change events with record_all_events' do
    let(:normal_metrics) do
      SolidQueueAutoscaler::Metrics::Result.new(
        queue_depth: 50,
        oldest_job_age_seconds: 60.0,
        jobs_per_minute: 100,
        claimed_jobs: 5,
        failed_jobs: 0,
        blocked_jobs: 0,
        active_workers: 3,
        queues_breakdown: { 'default' => 50 },
        collected_at: Time.current
      )
    end

    let(:no_change_decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :no_change,
        from: 3,
        to: 3,
        reason: 'metrics within normal range'
      )
    end

    before do
      allow(metrics_collector).to receive(:collect).and_return(normal_metrics)
      allow(decision_engine).to receive(:decide).and_return(no_change_decision)
      allow(adapter).to receive(:current_workers).and_return(3)
    end

    context 'when record_all_events is false (default)' do
      before do
        config.record_all_events = false
      end

      it 'does NOT record no_change events' do
        scaler = SolidQueueAutoscaler::Scaler.new(config: config)
        result = scaler.run

        expect(result.success?).to be(true)
        expect(result.scaled?).to be(false)
        expect(recorded_events).to be_empty
      end
    end

    context 'when record_all_events is true' do
      before do
        config.record_all_events = true
      end

      it 'records no_change events' do
        scaler = SolidQueueAutoscaler::Scaler.new(config: config)
        result = scaler.run

        expect(result.success?).to be(true)
        expect(result.scaled?).to be(false)
        expect(recorded_events.size).to eq(1)
        expect(recorded_events.first[:action]).to eq('no_change')
      end
    end
  end
end

RSpec.describe SolidQueueAutoscaler::ScaleEvent, '.diagnostics' do
  let(:connection) do
    double('connection').tap do |conn|
      allow(conn).to receive(:quote_table_name) { |name| name }
    end
  end

  describe 'diagnostic information' do
    before do
      allow(SolidQueueAutoscaler::ScaleEvent).to receive(:default_connection).and_return(connection)
    end

    context 'when everything is working' do
      before do
        allow(connection).to receive(:table_exists?).with('solid_queue_autoscaler_events').and_return(true)
        allow(connection).to receive(:select_value).and_return(42)
        allow(connection).to receive(:quote) { |v| v.nil? ? 'NULL' : "'#{v}'" }
      end

      it 'returns diagnostic info showing table exists' do
        diagnostics = SolidQueueAutoscaler::ScaleEvent.diagnostics(connection: connection)

        expect(diagnostics[:table_exists]).to be(true)
        expect(diagnostics[:event_count]).to eq(42)
        expect(diagnostics[:connection_class]).to be_present
      end
    end

    context 'when table does not exist' do
      before do
        allow(connection).to receive(:table_exists?).with('solid_queue_autoscaler_events').and_return(false)
      end

      it 'returns diagnostic info showing table missing' do
        diagnostics = SolidQueueAutoscaler::ScaleEvent.diagnostics(connection: connection)

        expect(diagnostics[:table_exists]).to be(false)
        expect(diagnostics[:event_count]).to eq(0)
        expect(diagnostics[:error]).to include('Table does not exist')
      end
    end

    context 'when connection raises error' do
      before do
        allow(connection).to receive(:table_exists?).and_raise(StandardError.new('Connection failed'))
      end

      it 'returns diagnostic info with error' do
        diagnostics = SolidQueueAutoscaler::ScaleEvent.diagnostics(connection: connection)

        expect(diagnostics[:table_exists]).to be(false)
        expect(diagnostics[:error]).to include('Connection failed')
      end
    end
  end
end
