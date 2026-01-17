# frozen_string_literal: true

require 'zlib'
require 'socket'

module SolidQueueAutoscaler
  # Advisory lock wrapper for singleton enforcement.
  # Supports both PostgreSQL (native advisory locks) and SQLite (table-based locks).
  #
  # IMPORTANT: PgBouncer Compatibility Warning (PostgreSQL only)
  # ============================================================
  # PostgreSQL advisory locks are connection-scoped (session-level locks).
  # If you're using PgBouncer in transaction pooling mode, advisory locks
  # will NOT work correctly because:
  #   1. Each query may run on a different backend connection
  #   2. The lock acquired on one connection won't be visible on another
  #   3. The lock may be "released" when returned to the pool
  #
  # Solutions:
  #   - Use PgBouncer in session pooling mode for the queue database
  #   - Use a direct connection (bypass PgBouncer) for the autoscaler
  #   - Disable advisory locks and use external coordination (Redis, etc.)
  #   - Set config.persist_cooldowns = false and rely on a single process
  #
  # If you're seeing multiple autoscalers running simultaneously or
  # lock acquisition always failing, PgBouncer is likely the cause.
  #
  class AdvisoryLock
    LOCKS_TABLE_NAME = 'solid_queue_autoscaler_locks'
    # Stale lock timeout - locks older than this are considered abandoned (5 minutes)
    STALE_LOCK_TIMEOUT_SECONDS = 300

    attr_reader :lock_key, :timeout

    def initialize(lock_key: nil, timeout: nil, config: nil)
      @config = config || SolidQueueAutoscaler.config
      @lock_key = lock_key || @config.lock_key
      @timeout = timeout || @config.lock_timeout_seconds
      @lock_acquired = false
      @strategy = nil
    end

    def with_lock
      acquire!
      yield
    ensure
      release
    end

    def try_lock
      return false if @lock_acquired

      @lock_acquired = lock_strategy.try_lock
      @lock_acquired
    end

    def acquire!
      return true if @lock_acquired

      @lock_acquired = lock_strategy.try_lock

      raise LockError, "Could not acquire advisory lock '#{lock_key}' (id: #{lock_id})" unless @lock_acquired

      true
    end

    def release
      return false unless @lock_acquired

      lock_strategy.release
      @lock_acquired = false
      true
    end

    def locked?
      @lock_acquired
    end

    private

    def connection
      @config.connection
    end

    def lock_id
      @lock_id ||= begin
        hash = Zlib.crc32(lock_key.to_s)
        hash & 0x7FFFFFFF
      end
    end

    def lock_strategy
      @strategy ||= create_lock_strategy
    end

    def create_lock_strategy
      adapter_name = connection.adapter_name.downcase

      case adapter_name
      when /postgresql/, /postgis/
        PostgreSQLLockStrategy.new(connection: connection, lock_id: lock_id, lock_key: lock_key)
      when /sqlite/
        SQLiteLockStrategy.new(connection: connection, lock_id: lock_id, lock_key: lock_key)
      when /mysql/, /trilogy/
        MySQLLockStrategy.new(connection: connection, lock_id: lock_id, lock_key: lock_key)
      else
        # Fall back to table-based locking for unknown adapters
        TableBasedLockStrategy.new(connection: connection, lock_id: lock_id, lock_key: lock_key)
      end
    end

    # Base class for lock strategies
    class BaseLockStrategy
      def initialize(connection:, lock_id:, lock_key:)
        @connection = connection
        @lock_id = lock_id
        @lock_key = lock_key
      end

      def try_lock
        raise NotImplementedError, "#{self.class} must implement #try_lock"
      end

      def release
        raise NotImplementedError, "#{self.class} must implement #release"
      end

      protected

      attr_reader :connection, :lock_id, :lock_key
    end

    # PostgreSQL native advisory locks
    class PostgreSQLLockStrategy < BaseLockStrategy
      def try_lock
        result = connection.select_value(
          "SELECT pg_try_advisory_lock(#{lock_id})"
        )
        [true, 't'].include?(result)
      end

      def release
        connection.execute("SELECT pg_advisory_unlock(#{lock_id})")
        true
      end
    end

    # MySQL named locks (GET_LOCK/RELEASE_LOCK)
    class MySQLLockStrategy < BaseLockStrategy
      def try_lock
        # MySQL GET_LOCK returns 1 on success, 0 if timeout, NULL on error
        result = connection.select_value(
          "SELECT GET_LOCK(#{connection.quote(lock_key)}, 0)"
        )
        result == 1
      end

      def release
        connection.execute("SELECT RELEASE_LOCK(#{connection.quote(lock_key)})")
        true
      end
    end

    # Table-based locking for databases without native advisory lock support
    # Uses a simple locks table with INSERT/DELETE for lock management
    class TableBasedLockStrategy < BaseLockStrategy
      def try_lock
        ensure_locks_table_exists!
        cleanup_stale_locks!

        # Try to insert a lock record
        begin
          connection.execute(<<~SQL)
            INSERT INTO #{quoted_table_name} (lock_key, lock_id, locked_at, locked_by)
            VALUES (#{connection.quote(lock_key)}, #{lock_id}, #{connection.quote(Time.now.utc.iso8601)}, #{connection.quote(lock_owner)})
          SQL
          true
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
          # Lock already held by another process
          # StatementInvalid catches SQLite's UNIQUE constraint violation
          return false if e.message.include?('UNIQUE') || e.message.include?('duplicate')

          raise
        end
      end

      def release
        return true unless table_exists?

        connection.execute(<<~SQL)
          DELETE FROM #{quoted_table_name}
          WHERE lock_key = #{connection.quote(lock_key)}
            AND locked_by = #{connection.quote(lock_owner)}
        SQL
        true
      end

      private

      def ensure_locks_table_exists!
        return if table_exists?

        create_locks_table!
      end

      def table_exists?
        @table_exists ||= connection.table_exists?(LOCKS_TABLE_NAME)
      end

      def create_locks_table!
        connection.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS #{quoted_table_name} (
            lock_key VARCHAR(255) NOT NULL PRIMARY KEY,
            lock_id INTEGER NOT NULL,
            locked_at DATETIME NOT NULL,
            locked_by VARCHAR(255) NOT NULL
          )
        SQL
        @table_exists = true
      end

      def cleanup_stale_locks!
        # Remove locks older than STALE_LOCK_TIMEOUT_SECONDS
        stale_threshold = (Time.now.utc - STALE_LOCK_TIMEOUT_SECONDS).iso8601
        connection.execute(<<~SQL)
          DELETE FROM #{quoted_table_name}
          WHERE locked_at < #{connection.quote(stale_threshold)}
        SQL
      end

      def quoted_table_name
        connection.quote_table_name(LOCKS_TABLE_NAME)
      end

      def lock_owner
        # Unique identifier for this process/thread
        @lock_owner ||= "#{Socket.gethostname}:#{Process.pid}:#{Thread.current.object_id}"
      end
    end

    # SQLite table-based locking (SQLite doesn't have advisory locks)
    # Defined after TableBasedLockStrategy since it inherits from it
    class SQLiteLockStrategy < TableBasedLockStrategy
      # Inherits all behavior from TableBasedLockStrategy
    end
  end
end
