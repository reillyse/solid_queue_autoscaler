# frozen_string_literal: true

require 'spec_helper'
require 'active_record'

RSpec.describe SolidQueueAutoscaler::AdvisoryLock do
  let(:config) do
    instance_double(
      SolidQueueAutoscaler::Configuration,
      lock_key: 'test_lock',
      lock_timeout_seconds: 30,
      connection: connection
    )
  end

  describe 'lock strategy detection' do
    context 'with PostgreSQL adapter' do
      let(:connection) do
        instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter,
                        adapter_name: 'PostgreSQL')
      end

      it 'uses PostgreSQLLockStrategy' do
        lock = described_class.new(config: config)
        strategy = lock.send(:lock_strategy)
        expect(strategy).to be_a(described_class::PostgreSQLLockStrategy)
      end
    end

    context 'with PostGIS adapter' do
      let(:connection) do
        instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter,
                        adapter_name: 'PostGIS')
      end

      it 'uses PostgreSQLLockStrategy' do
        lock = described_class.new(config: config)
        strategy = lock.send(:lock_strategy)
        expect(strategy).to be_a(described_class::PostgreSQLLockStrategy)
      end
    end

    context 'with SQLite adapter' do
      let(:connection) do
        instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter,
                        adapter_name: 'SQLite')
      end

      it 'uses SQLiteLockStrategy' do
        lock = described_class.new(config: config)
        strategy = lock.send(:lock_strategy)
        expect(strategy).to be_a(described_class::SQLiteLockStrategy)
      end
    end

    context 'with MySQL adapter' do
      let(:connection) do
        instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter,
                        adapter_name: 'Mysql2')
      end

      it 'uses MySQLLockStrategy' do
        lock = described_class.new(config: config)
        strategy = lock.send(:lock_strategy)
        expect(strategy).to be_a(described_class::MySQLLockStrategy)
      end
    end

    context 'with Trilogy adapter' do
      let(:connection) do
        instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter,
                        adapter_name: 'Trilogy')
      end

      it 'uses MySQLLockStrategy' do
        lock = described_class.new(config: config)
        strategy = lock.send(:lock_strategy)
        expect(strategy).to be_a(described_class::MySQLLockStrategy)
      end
    end

    context 'with unknown adapter' do
      let(:connection) do
        instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter,
                        adapter_name: 'UnknownDB')
      end

      it 'falls back to TableBasedLockStrategy' do
        lock = described_class.new(config: config)
        strategy = lock.send(:lock_strategy)
        expect(strategy).to be_a(described_class::TableBasedLockStrategy)
      end
    end
  end

  describe 'PostgreSQLLockStrategy' do
    let(:connection) do
      instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter,
                      adapter_name: 'PostgreSQL')
    end

    let(:lock) { described_class.new(config: config) }

    describe '#try_lock' do
      it 'acquires the lock when available' do
        allow(connection).to receive(:select_value).and_return(true)

        expect(lock.try_lock).to be true
        expect(lock.locked?).to be true
      end

      it 'returns false when lock is not available' do
        allow(connection).to receive(:select_value).and_return(false)

        expect(lock.try_lock).to be false
        expect(lock.locked?).to be false
      end

      it 'returns false when already locked' do
        allow(connection).to receive(:select_value).and_return(true)
        lock.try_lock

        expect(lock.try_lock).to be false
      end
    end

    describe '#acquire!' do
      it 'acquires the lock when available' do
        allow(connection).to receive(:select_value).and_return(true)

        expect(lock.acquire!).to be true
        expect(lock.locked?).to be true
      end

      it 'raises LockError when lock is not available' do
        allow(connection).to receive(:select_value).and_return(false)

        expect { lock.acquire! }.to raise_error(SolidQueueAutoscaler::LockError)
      end
    end

    describe '#release' do
      it 'releases the lock when locked' do
        allow(connection).to receive(:select_value).and_return(true)
        allow(connection).to receive(:execute)
        lock.try_lock

        expect(lock.release).to be true
        expect(lock.locked?).to be false
      end

      it 'returns false when not locked' do
        expect(lock.release).to be false
      end
    end

    describe '#with_lock' do
      it 'acquires lock, yields, and releases' do
        allow(connection).to receive(:select_value).and_return(true)
        allow(connection).to receive(:execute)

        yielded = false
        lock.with_lock { yielded = true }

        expect(yielded).to be true
        expect(lock.locked?).to be false
      end

      it 'releases lock even if block raises' do
        allow(connection).to receive(:select_value).and_return(true)
        allow(connection).to receive(:execute)

        expect do
          lock.with_lock { raise 'error' }
        end.to raise_error('error')

        expect(lock.locked?).to be false
      end
    end
  end

  describe 'MySQLLockStrategy' do
    let(:connection) do
      instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter,
                      adapter_name: 'Mysql2')
    end

    let(:lock) { described_class.new(config: config) }

    describe '#try_lock' do
      it 'acquires the lock when GET_LOCK returns 1' do
        allow(connection).to receive(:quote).with('test_lock').and_return("'test_lock'")
        allow(connection).to receive(:select_value).and_return(1)

        expect(lock.try_lock).to be true
        expect(lock.locked?).to be true
      end

      it 'returns false when GET_LOCK returns 0' do
        allow(connection).to receive(:quote).with('test_lock').and_return("'test_lock'")
        allow(connection).to receive(:select_value).and_return(0)

        expect(lock.try_lock).to be false
        expect(lock.locked?).to be false
      end
    end

    describe '#release' do
      it 'calls RELEASE_LOCK when locked' do
        allow(connection).to receive(:quote).with('test_lock').and_return("'test_lock'")
        allow(connection).to receive(:select_value).and_return(1)
        allow(connection).to receive(:execute)
        lock.try_lock

        expect(connection).to receive(:execute).with("SELECT RELEASE_LOCK('test_lock')")
        lock.release
      end
    end
  end

  describe 'lock_id generation' do
    let(:connection) do
      instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter,
                      adapter_name: 'PostgreSQL')
    end

    it 'generates consistent lock_id for the same key' do
      lock1 = described_class.new(lock_key: 'my_key', config: config)
      lock2 = described_class.new(lock_key: 'my_key', config: config)

      expect(lock1.send(:lock_id)).to eq(lock2.send(:lock_id))
    end

    it 'generates different lock_id for different keys' do
      lock1 = described_class.new(lock_key: 'key1', config: config)
      lock2 = described_class.new(lock_key: 'key2', config: config)

      expect(lock1.send(:lock_id)).not_to eq(lock2.send(:lock_id))
    end

    it 'generates positive integers only' do
      lock = described_class.new(lock_key: 'test', config: config)
      lock_id = lock.send(:lock_id)

      expect(lock_id).to be_a(Integer)
      expect(lock_id).to be >= 0
      expect(lock_id).to be <= 0x7FFFFFFF
    end
  end
end
