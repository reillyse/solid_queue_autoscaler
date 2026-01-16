# frozen_string_literal: true

RSpec.describe SolidQueueAutoscaler::ScaleEvent do
  let(:connection) { double('connection') }

  describe 'constants' do
    it 'has TABLE_NAME defined' do
      expect(described_class::TABLE_NAME).to eq('solid_queue_autoscaler_events')
    end

    it 'has ACTIONS defined' do
      expect(described_class::ACTIONS).to include('scale_up', 'scale_down', 'no_change', 'skipped', 'error')
    end
  end

  describe '#initialize' do
    let(:attrs) do
      {
        id: 1,
        worker_name: 'default',
        action: 'scale_up',
        from_workers: 2,
        to_workers: 3,
        reason: 'queue_depth high',
        queue_depth: 150,
        latency_seconds: 60.5,
        metrics_json: '{"queue_depth":150}',
        dry_run: false,
        created_at: Time.current
      }
    end

    subject(:event) { described_class.new(attrs) }

    it 'sets all attributes' do
      expect(event.id).to eq(1)
      expect(event.worker_name).to eq('default')
      expect(event.action).to eq('scale_up')
      expect(event.from_workers).to eq(2)
      expect(event.to_workers).to eq(3)
      expect(event.reason).to eq('queue_depth high')
      expect(event.queue_depth).to eq(150)
      expect(event.latency_seconds).to eq(60.5)
      expect(event.metrics_json).to eq('{"queue_depth":150}')
      expect(event.dry_run).to be(false)
      expect(event.created_at).to be_present
    end

    it 'handles empty attributes' do
      event = described_class.new({})
      expect(event.id).to be_nil
      expect(event.worker_name).to be_nil
      expect(event.action).to be_nil
    end
  end

  describe '#scaled?' do
    it 'returns true for scale_up' do
      event = described_class.new(action: 'scale_up')
      expect(event.scaled?).to be(true)
    end

    it 'returns true for scale_down' do
      event = described_class.new(action: 'scale_down')
      expect(event.scaled?).to be(true)
    end

    it 'returns false for no_change' do
      event = described_class.new(action: 'no_change')
      expect(event.scaled?).to be(false)
    end

    it 'returns false for skipped' do
      event = described_class.new(action: 'skipped')
      expect(event.scaled?).to be(false)
    end

    it 'returns false for error' do
      event = described_class.new(action: 'error')
      expect(event.scaled?).to be(false)
    end
  end

  describe '#scale_up?' do
    it 'returns true for scale_up action' do
      event = described_class.new(action: 'scale_up')
      expect(event.scale_up?).to be(true)
    end

    it 'returns false for other actions' do
      event = described_class.new(action: 'scale_down')
      expect(event.scale_up?).to be(false)
    end
  end

  describe '#scale_down?' do
    it 'returns true for scale_down action' do
      event = described_class.new(action: 'scale_down')
      expect(event.scale_down?).to be(true)
    end

    it 'returns false for other actions' do
      event = described_class.new(action: 'scale_up')
      expect(event.scale_down?).to be(false)
    end
  end

  describe '#metrics' do
    it 'parses valid JSON' do
      event = described_class.new(metrics_json: '{"queue_depth":150,"latency":60}')
      expect(event.metrics).to eq({ queue_depth: 150, latency: 60 })
    end

    it 'returns nil for nil metrics_json' do
      event = described_class.new(metrics_json: nil)
      expect(event.metrics).to be_nil
    end

    it 'returns nil for invalid JSON' do
      event = described_class.new(metrics_json: 'invalid json {')
      expect(event.metrics).to be_nil
    end

    it 'returns nil for empty string' do
      event = described_class.new(metrics_json: '')
      expect(event.metrics).to be_nil
    end
  end

  describe '.table_exists?' do
    it 'returns true when table exists' do
      allow(connection).to receive(:table_exists?)
        .with('solid_queue_autoscaler_events')
        .and_return(true)

      expect(described_class.table_exists?(connection)).to be(true)
    end

    it 'returns false when table does not exist' do
      allow(connection).to receive(:table_exists?)
        .with('solid_queue_autoscaler_events')
        .and_return(false)

      expect(described_class.table_exists?(connection)).to be(false)
    end

    it 'returns false when connection raises error' do
      allow(connection).to receive(:table_exists?).and_raise(StandardError.new('Connection error'))

      expect(described_class.table_exists?(connection)).to be(false)
    end
  end

  describe '.create!' do
    let(:attrs) do
      {
        worker_name: 'default',
        action: 'scale_up',
        from_workers: 2,
        to_workers: 3,
        reason: 'queue_depth high',
        queue_depth: 150,
        latency_seconds: 60.5,
        metrics_json: '{"queue_depth":150}',
        dry_run: false
      }
    end

    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote) { |v| "'#{v}'" }
    end

    it 'creates an event when table exists' do
      result = double('result', first: { 'id' => 1 })
      allow(connection).to receive(:execute).and_return(result)

      event = described_class.create!(attrs, connection: connection)

      expect(event).to be_a(described_class)
      expect(event.worker_name).to eq('default')
      expect(event.action).to eq('scale_up')
      expect(event.id).to eq(1)
    end

    it 'returns nil when table does not exist' do
      allow(connection).to receive(:table_exists?).and_return(false)

      event = described_class.create!(attrs, connection: connection)

      expect(event).to be_nil
    end

    it 'returns nil and does not raise when error occurs' do
      allow(connection).to receive(:execute).and_raise(StandardError.new('DB error'))

      event = described_class.create!(attrs, connection: connection)

      expect(event).to be_nil
    end

    it 'executes INSERT SQL with correct values' do
      result = double('result', first: { 'id' => 1 })
      allow(connection).to receive(:execute).and_return(result)

      described_class.create!(attrs, connection: connection)

      expect(connection).to have_received(:execute).with(/INSERT INTO solid_queue_autoscaler_events/)
    end
  end

  describe '.recent' do
    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote) { |v| "'#{v}'" }
    end

    it 'returns events ordered by created_at DESC' do
      rows = [
        {
          'id' => 2, 'worker_name' => 'default', 'action' => 'scale_down',
          'from_workers' => 3, 'to_workers' => 2, 'reason' => 'low queue',
          'queue_depth' => 5, 'latency_seconds' => 10.0, 'metrics_json' => nil,
          'dry_run' => false, 'created_at' => Time.current.to_s
        },
        {
          'id' => 1, 'worker_name' => 'default', 'action' => 'scale_up',
          'from_workers' => 2, 'to_workers' => 3, 'reason' => 'high queue',
          'queue_depth' => 150, 'latency_seconds' => 60.0, 'metrics_json' => nil,
          'dry_run' => false, 'created_at' => (Time.current - 1.hour).to_s
        }
      ]
      allow(connection).to receive(:select_all).and_return(rows)

      events = described_class.recent(limit: 10, connection: connection)

      expect(events.size).to eq(2)
      expect(events.first.id).to eq(2)
      expect(events.last.id).to eq(1)
    end

    it 'filters by worker_name when provided' do
      allow(connection).to receive(:select_all).and_return([])

      described_class.recent(limit: 10, worker_name: 'critical_worker', connection: connection)

      expect(connection).to have_received(:select_all).with(/WHERE worker_name = 'critical_worker'/)
    end

    it 'returns empty array when table does not exist' do
      allow(connection).to receive(:table_exists?).and_return(false)

      events = described_class.recent(connection: connection)

      expect(events).to eq([])
    end

    it 'returns empty array when error occurs' do
      allow(connection).to receive(:select_all).and_raise(StandardError.new('Query error'))

      events = described_class.recent(connection: connection)

      expect(events).to eq([])
    end
  end

  describe '.by_action' do
    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote) { |v| "'#{v}'" }
    end

    it 'filters events by action type' do
      rows = [
        {
          'id' => 1, 'worker_name' => 'default', 'action' => 'scale_up',
          'from_workers' => 2, 'to_workers' => 3, 'reason' => 'high queue',
          'queue_depth' => 150, 'latency_seconds' => 60.0, 'metrics_json' => nil,
          'dry_run' => false, 'created_at' => Time.current.to_s
        }
      ]
      allow(connection).to receive(:select_all).and_return(rows)

      events = described_class.by_action('scale_up', connection: connection)

      expect(events.size).to eq(1)
      expect(events.first.action).to eq('scale_up')
    end

    it 'returns empty array when table does not exist' do
      allow(connection).to receive(:table_exists?).and_return(false)

      events = described_class.by_action('scale_up', connection: connection)

      expect(events).to eq([])
    end
  end

  describe '.stats' do
    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote) { |v| "'#{v}'" }
    end

    it 'returns aggregated statistics' do
      rows = [
        { 'action' => 'scale_up', 'count' => 5, 'avg_queue_depth' => 150.0, 'avg_latency' => 60.0 },
        { 'action' => 'scale_down', 'count' => 3, 'avg_queue_depth' => 10.0, 'avg_latency' => 5.0 }
      ]
      allow(connection).to receive(:select_all).and_return(double(to_a: rows))

      stats = described_class.stats(connection: connection)

      expect(stats[:total]).to eq(8)
      expect(stats[:scale_up_count]).to eq(5)
      expect(stats[:scale_down_count]).to eq(3)
    end

    it 'returns default stats when table does not exist' do
      allow(connection).to receive(:table_exists?).and_return(false)

      stats = described_class.stats(connection: connection)

      expect(stats[:total]).to eq(0)
      expect(stats[:scale_up_count]).to eq(0)
    end

    it 'filters by worker_name when provided' do
      allow(connection).to receive(:select_all).and_return(double(to_a: []))

      described_class.stats(worker_name: 'critical', connection: connection)

      expect(connection).to have_received(:select_all).with(/AND worker_name = 'critical'/)
    end

    it 'returns default stats when error occurs' do
      allow(connection).to receive(:select_all).and_raise(StandardError.new('Query error'))

      stats = described_class.stats(connection: connection)

      expect(stats[:total]).to eq(0)
    end
  end

  describe '.cleanup!' do
    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote) { |v| "'#{v}'" }
    end

    it 'deletes old events and returns count' do
      result = double('result', cmd_tuples: 10)
      allow(connection).to receive(:execute).and_return(result)

      deleted = described_class.cleanup!(keep_days: 30, connection: connection)

      expect(deleted).to eq(10)
    end

    it 'executes DELETE SQL with correct cutoff date' do
      result = double('result', cmd_tuples: 0)
      allow(connection).to receive(:execute).and_return(result)

      described_class.cleanup!(keep_days: 7, connection: connection)

      expect(connection).to have_received(:execute).with(/DELETE FROM solid_queue_autoscaler_events/)
    end

    it 'returns 0 when table does not exist' do
      allow(connection).to receive(:table_exists?).and_return(false)

      deleted = described_class.cleanup!(connection: connection)

      expect(deleted).to eq(0)
    end

    it 'returns 0 when error occurs' do
      allow(connection).to receive(:execute).and_raise(StandardError.new('DB error'))

      deleted = described_class.cleanup!(connection: connection)

      expect(deleted).to eq(0)
    end
  end

  describe '.count' do
    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote) { |v| "'#{v}'" }
    end

    it 'returns total count when no time filter' do
      allow(connection).to receive(:select_value).and_return(42)

      count = described_class.count(connection: connection)

      expect(count).to eq(42)
    end

    it 'returns filtered count when since is provided' do
      allow(connection).to receive(:select_value).and_return(10)

      count = described_class.count(since: 1.hour.ago, connection: connection)

      expect(count).to eq(10)
      expect(connection).to have_received(:select_value).with(/WHERE created_at >=/)
    end

    it 'returns 0 when table does not exist' do
      allow(connection).to receive(:table_exists?).and_return(false)

      count = described_class.count(connection: connection)

      expect(count).to eq(0)
    end

    it 'returns 0 when error occurs' do
      allow(connection).to receive(:select_value).and_raise(StandardError.new('Query error'))

      count = described_class.count(connection: connection)

      expect(count).to eq(0)
    end
  end

  describe 'private helper methods' do
    describe '.parse_boolean' do
      it 'parses true values' do
        expect(described_class.send(:parse_boolean, true)).to be(true)
        expect(described_class.send(:parse_boolean, 't')).to be(true)
        expect(described_class.send(:parse_boolean, 'true')).to be(true)
        expect(described_class.send(:parse_boolean, '1')).to be(true)
        expect(described_class.send(:parse_boolean, 1)).to be(true)
      end

      it 'parses false values' do
        expect(described_class.send(:parse_boolean, false)).to be(false)
        expect(described_class.send(:parse_boolean, 'f')).to be(false)
        expect(described_class.send(:parse_boolean, 'false')).to be(false)
        expect(described_class.send(:parse_boolean, '0')).to be(false)
        expect(described_class.send(:parse_boolean, 0)).to be(false)
        expect(described_class.send(:parse_boolean, nil)).to be(false)
      end
    end

    describe '.parse_time' do
      it 'parses Time objects' do
        time = Time.current
        expect(described_class.send(:parse_time, time)).to eq(time)
      end

      it 'parses DateTime objects' do
        datetime = DateTime.current
        result = described_class.send(:parse_time, datetime)
        expect(result).to be_a(Time)
      end

      it 'parses string timestamps' do
        time_str = '2024-01-15 10:30:00 UTC'
        result = described_class.send(:parse_time, time_str)
        expect(result).to be_a(Time)
      end

      it 'returns nil for nil input' do
        expect(described_class.send(:parse_time, nil)).to be_nil
      end
    end
  end
end
