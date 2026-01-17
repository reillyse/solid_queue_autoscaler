# frozen_string_literal: true

require 'spec_helper'
require 'active_record'

# Check if SQLite is available and compatible
SQLITE3_AVAILABLE = begin
  require 'sqlite3'
  # Try to establish a test connection to verify compatibility
  ActiveRecord::Base.establish_connection(
    adapter: 'sqlite3',
    database: ':memory:'
  )
  ActiveRecord::Base.connection.active?
rescue LoadError, ActiveRecord::ConnectionNotEstablished, StandardError => e
  # Log the error for debugging
  warn "SQLite tests skipped: #{e.message}" if ENV['DEBUG']
  false
end

RSpec.describe 'SQLite Table-Based Locking Integration', :sqlite do
  # Skip all tests if SQLite is not available
  before(:all) do
    skip 'SQLite3 gem not available or incompatible' unless SQLITE3_AVAILABLE
  end

  let(:db_file) { ':memory:' }
  let(:connection) { ActiveRecord::Base.connection }

  after(:each) do
    # Clean up any locks created during tests
    if connection.table_exists?('solid_queue_autoscaler_locks')
      connection.execute('DELETE FROM solid_queue_autoscaler_locks')
    end
  end

  let(:config) do
    instance_double(
      SolidQueueAutoscaler::Configuration,
      lock_key: 'test_sqlite_lock',
      lock_timeout_seconds: 30,
      connection: connection
    )
  end

  describe 'lock strategy detection' do
    it 'detects SQLite and uses SQLiteLockStrategy' do
      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)
      strategy = lock.send(:lock_strategy)

      expect(strategy).to be_a(SolidQueueAutoscaler::AdvisoryLock::SQLiteLockStrategy)
    end
  end

  describe 'auto-creating locks table' do
    it 'creates the locks table on first lock attempt' do
      # Table shouldn't exist yet (fresh database)
      # Actually with in-memory DB it might exist from previous tests, so let's drop it
      connection.execute('DROP TABLE IF EXISTS solid_queue_autoscaler_locks')

      expect(connection.table_exists?('solid_queue_autoscaler_locks')).to be false

      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)
      lock.try_lock

      expect(connection.table_exists?('solid_queue_autoscaler_locks')).to be true
    end

    it 'creates table with correct columns' do
      connection.execute('DROP TABLE IF EXISTS solid_queue_autoscaler_locks')

      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)
      lock.try_lock
      lock.release

      columns = connection.columns('solid_queue_autoscaler_locks').map(&:name)
      expect(columns).to include('lock_key', 'lock_id', 'locked_at', 'locked_by')
    end
  end

  describe 'acquiring locks' do
    it 'successfully acquires a lock' do
      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)

      expect(lock.try_lock).to be true
      expect(lock.locked?).to be true
    end

    it 'prevents double-acquisition from same instance' do
      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)
      lock.try_lock

      # Same instance should return false (already holding lock)
      expect(lock.try_lock).to be false
    end

    it 'prevents acquisition when lock is held by another instance' do
      lock1 = SolidQueueAutoscaler::AdvisoryLock.new(config: config)
      lock2 = SolidQueueAutoscaler::AdvisoryLock.new(config: config)

      expect(lock1.try_lock).to be true
      expect(lock2.try_lock).to be false
    end

    it 'allows acquisition after lock is released' do
      lock1 = SolidQueueAutoscaler::AdvisoryLock.new(config: config)
      lock2 = SolidQueueAutoscaler::AdvisoryLock.new(config: config)

      lock1.try_lock
      lock1.release

      expect(lock2.try_lock).to be true
    end
  end

  describe 'releasing locks' do
    it 'successfully releases a lock' do
      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)
      lock.try_lock

      expect(lock.release).to be true
      expect(lock.locked?).to be false
    end

    it 'returns false when releasing a lock not held' do
      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)

      expect(lock.release).to be false
    end

    it 'only releases own lock' do
      lock1_config = instance_double(
        SolidQueueAutoscaler::Configuration,
        lock_key: 'shared_lock',
        lock_timeout_seconds: 30,
        connection: connection
      )

      lock1 = SolidQueueAutoscaler::AdvisoryLock.new(config: lock1_config)
      lock2 = SolidQueueAutoscaler::AdvisoryLock.new(config: lock1_config)

      lock1.try_lock

      # lock2 never acquired, so release should be no-op
      expect(lock2.release).to be false

      # lock1's lock should still be held
      expect(lock2.try_lock).to be false
    end
  end

  describe 'with_lock block' do
    it 'acquires lock for duration of block' do
      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)

      lock.with_lock do
        expect(lock.locked?).to be true
      end

      expect(lock.locked?).to be false
    end

    it 'releases lock even if block raises' do
      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)

      expect do
        lock.with_lock do
          raise 'test error'
        end
      end.to raise_error('test error')

      expect(lock.locked?).to be false
    end
  end

  describe 'stale lock cleanup' do
    it 'cleans up stale locks older than timeout' do
      # Insert a stale lock directly
      old_time = (Time.now.utc - 600).iso8601 # 10 minutes ago
      connection.execute('DROP TABLE IF EXISTS solid_queue_autoscaler_locks')

      # Create the table manually
      connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS solid_queue_autoscaler_locks (
          lock_key VARCHAR(255) NOT NULL PRIMARY KEY,
          lock_id INTEGER NOT NULL,
          locked_at DATETIME NOT NULL,
          locked_by VARCHAR(255) NOT NULL
        )
      SQL

      # Insert a stale lock
      connection.execute(<<~SQL)
        INSERT INTO solid_queue_autoscaler_locks (lock_key, lock_id, locked_at, locked_by)
        VALUES ('test_sqlite_lock', 12345, '#{old_time}', 'stale_process:1234:5678')
      SQL

      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)

      # Should be able to acquire the lock because the stale one gets cleaned up
      expect(lock.try_lock).to be true
    end
  end

  describe 'multiple independent locks' do
    it 'allows different lock keys to be acquired independently' do
      config1 = instance_double(
        SolidQueueAutoscaler::Configuration,
        lock_key: 'lock_1',
        lock_timeout_seconds: 30,
        connection: connection
      )

      config2 = instance_double(
        SolidQueueAutoscaler::Configuration,
        lock_key: 'lock_2',
        lock_timeout_seconds: 30,
        connection: connection
      )

      lock1 = SolidQueueAutoscaler::AdvisoryLock.new(config: config1)
      lock2 = SolidQueueAutoscaler::AdvisoryLock.new(config: config2)

      expect(lock1.try_lock).to be true
      expect(lock2.try_lock).to be true

      lock1.release
      lock2.release
    end
  end

  describe 'acquire! method' do
    it 'raises LockError when cannot acquire' do
      lock1 = SolidQueueAutoscaler::AdvisoryLock.new(config: config)
      lock2 = SolidQueueAutoscaler::AdvisoryLock.new(config: config)

      lock1.try_lock

      expect { lock2.acquire! }.to raise_error(SolidQueueAutoscaler::LockError)
    end

    it 'returns true when lock is acquired' do
      lock = SolidQueueAutoscaler::AdvisoryLock.new(config: config)

      expect(lock.acquire!).to be true
    end
  end
end
