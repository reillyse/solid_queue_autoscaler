# frozen_string_literal: true

require 'zlib'

module SolidQueueAutoscaler
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
