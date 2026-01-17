# frozen_string_literal: true

RSpec.describe SolidQueueAutoscaler::CooldownTracker do
  let(:config) do
    configure_autoscaler(
      cooldown_seconds: 120,
      scale_up_cooldown_seconds: 60,
      scale_down_cooldown_seconds: 180
    )
    SolidQueueAutoscaler.config
  end

  let(:connection) do
    double('connection').tap do |conn|
      allow(conn).to receive(:quote_table_name) { |name| name }
    end
  end

  subject(:tracker) { described_class.new(config: config) }

  before do
    allow(config).to receive(:connection).and_return(connection)
  end

  describe '#table_exists?' do
    it 'returns true when table exists' do
      allow(connection).to receive(:table_exists?).with('solid_queue_autoscaler_state').and_return(true)
      expect(tracker.table_exists?).to be(true)
    end

    it 'returns false when table does not exist' do
      allow(connection).to receive(:table_exists?).with('solid_queue_autoscaler_state').and_return(false)
      expect(tracker.table_exists?).to be(false)
    end

    it 'caches the result' do
      allow(connection).to receive(:table_exists?).with('solid_queue_autoscaler_state').and_return(true)
      tracker.table_exists?
      tracker.table_exists?
      expect(connection).to have_received(:table_exists?).once
    end
  end

  describe '#last_scale_up_at' do
    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote).and_return("'default'")
    end

    it 'returns nil when no record exists' do
      allow(connection).to receive(:select_value).and_return(nil)
      expect(tracker.last_scale_up_at).to be_nil
    end

    it 'returns time when record exists' do
      time = Time.current
      allow(connection).to receive(:select_value).and_return(time.to_s)
      result = tracker.last_scale_up_at
      expect(result).to be_within(1.second).of(time)
    end

    it 'returns nil when table does not exist' do
      allow(connection).to receive(:table_exists?).and_return(false)
      expect(tracker.last_scale_up_at).to be_nil
    end
  end

  describe '#cooldown_active_for_scale_up?' do
    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote).and_return("'default'")
    end

    it 'returns false when no previous scale up' do
      allow(connection).to receive(:select_value).and_return(nil)
      expect(tracker.cooldown_active_for_scale_up?).to be(false)
    end

    it 'returns true when within cooldown period' do
      recent_time = (Time.current - 30.seconds).to_s
      allow(connection).to receive(:select_value).and_return(recent_time)
      expect(tracker.cooldown_active_for_scale_up?).to be(true)
    end

    it 'returns false when cooldown has expired' do
      old_time = (Time.current - 120.seconds).to_s
      allow(connection).to receive(:select_value).and_return(old_time)
      expect(tracker.cooldown_active_for_scale_up?).to be(false)
    end
  end

  describe '#scale_up_cooldown_remaining' do
    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote).and_return("'default'")
    end

    it 'returns 0 when no previous scale up' do
      allow(connection).to receive(:select_value).and_return(nil)
      expect(tracker.scale_up_cooldown_remaining).to eq(0)
    end

    it 'returns remaining time when within cooldown' do
      recent_time = (Time.current - 30.seconds).to_s
      allow(connection).to receive(:select_value).and_return(recent_time)
      remaining = tracker.scale_up_cooldown_remaining
      expect(remaining).to be_within(1).of(30)
    end

    it 'returns 0 when cooldown has expired' do
      old_time = (Time.current - 120.seconds).to_s
      allow(connection).to receive(:select_value).and_return(old_time)
      expect(tracker.scale_up_cooldown_remaining).to eq(0)
    end
  end

  describe '#record_scale_up!' do
    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote).and_return("'value'")
      allow(connection).to receive(:execute)
    end

    it 'returns true and executes upsert' do
      expect(tracker.record_scale_up!).to be(true)
      expect(connection).to have_received(:execute)
    end

    it 'returns false when table does not exist' do
      allow(connection).to receive(:table_exists?).and_return(false)
      expect(tracker.record_scale_up!).to be(false)
    end
  end

  describe '#reset!' do
    before do
      allow(connection).to receive(:table_exists?).and_return(true)
      allow(connection).to receive(:quote).and_return("'default'")
      allow(connection).to receive(:execute)
    end

    it 'deletes the state record' do
      expect(tracker.reset!).to be(true)
      expect(connection).to have_received(:execute).with(/DELETE FROM/)
    end

    it 'returns false when table does not exist' do
      allow(connection).to receive(:table_exists?).and_return(false)
      expect(tracker.reset!).to be(false)
    end
  end
end
