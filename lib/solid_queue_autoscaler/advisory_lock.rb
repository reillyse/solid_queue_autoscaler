# frozen_string_literal: true

require 'zlib'

module SolidQueueAutoscaler
  # PostgreSQL advisory lock wrapper for singleton enforcement.
  #
  # IMPORTANT: PgBouncer Compatibility Warning
  # ==========================================
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
    attr_reader :lock_key, :timeout

    def initialize(lock_key: nil, timeout: nil, config: nil)
      @config = config || SolidQueueAutoscaler.config
      @lock_key = lock_key || @config.lock_key
      @timeout = timeout || @config.lock_timeout_seconds
      @lock_acquired = false
    end

    def with_lock
      acquire!
      yield
    ensure
      release
    end

    def try_lock
      return false if @lock_acquired

      result = connection.select_value(
        "SELECT pg_try_advisory_lock(#{lock_id})"
      )
      @lock_acquired = [true, 't'].include?(result)
      @lock_acquired
    end

    def acquire!
      return true if @lock_acquired

      result = connection.select_value(
        "SELECT pg_try_advisory_lock(#{lock_id})"
      )
      @lock_acquired = [true, 't'].include?(result)

      raise LockError, "Could not acquire advisory lock '#{lock_key}' (id: #{lock_id})" unless @lock_acquired

      true
    end

    def release
      return false unless @lock_acquired

      connection.execute("SELECT pg_advisory_unlock(#{lock_id})")
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
  end
end
