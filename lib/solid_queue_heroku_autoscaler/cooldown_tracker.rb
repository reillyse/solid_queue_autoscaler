# frozen_string_literal: true

require 'time'

module SolidQueueHerokuAutoscaler
  class CooldownTracker
    TABLE_NAME = 'solid_queue_autoscaler_state'
    DEFAULT_KEY = 'default'

    attr_reader :key

    def initialize(config: nil, key: DEFAULT_KEY)
      @config = config || SolidQueueHerokuAutoscaler.config
      @key = key
      @table_exists = nil
    end

    def last_scale_up_at
      return nil unless table_exists?

      result = connection.select_value(<<~SQL)
        SELECT last_scale_up_at FROM #{TABLE_NAME}
        WHERE key = #{connection.quote(key)}
      SQL
      result ? Time.parse(result.to_s) : nil
    rescue ArgumentError
      nil
    end

    def last_scale_down_at
      return nil unless table_exists?

      result = connection.select_value(<<~SQL)
        SELECT last_scale_down_at FROM #{TABLE_NAME}
        WHERE key = #{connection.quote(key)}
      SQL
      result ? Time.parse(result.to_s) : nil
    rescue ArgumentError
      nil
    end

    def record_scale_up!
      return false unless table_exists?

      upsert_state(last_scale_up_at: Time.current)
      true
    end

    def record_scale_down!
      return false unless table_exists?

      upsert_state(last_scale_down_at: Time.current)
      true
    end

    def reset!
      return false unless table_exists?

      connection.execute(<<~SQL)
        DELETE FROM #{TABLE_NAME} WHERE key = #{connection.quote(key)}
      SQL
      true
    end

    def cooldown_active_for_scale_up?
      last = last_scale_up_at
      return false unless last

      Time.current - last < @config.effective_scale_up_cooldown
    end

    def cooldown_active_for_scale_down?
      last = last_scale_down_at
      return false unless last

      Time.current - last < @config.effective_scale_down_cooldown
    end

    def scale_up_cooldown_remaining
      last = last_scale_up_at
      return 0 unless last

      remaining = @config.effective_scale_up_cooldown - (Time.current - last)
      [remaining, 0].max
    end

    def scale_down_cooldown_remaining
      last = last_scale_down_at
      return 0 unless last

      remaining = @config.effective_scale_down_cooldown - (Time.current - last)
      [remaining, 0].max
    end

    def table_exists?
      return @table_exists unless @table_exists.nil?

      @table_exists = connection.table_exists?(TABLE_NAME)
    rescue StandardError
      @table_exists = false
    end

    def state
      return {} unless table_exists?

      row = connection.select_one(<<~SQL)
        SELECT last_scale_up_at, last_scale_down_at, updated_at
        FROM #{TABLE_NAME}
        WHERE key = #{connection.quote(key)}
      SQL

      return {} unless row

      {
        last_scale_up_at: row['last_scale_up_at'],
        last_scale_down_at: row['last_scale_down_at'],
        updated_at: row['updated_at']
      }
    end

    private

    def connection
      @config.connection
    end

    def upsert_state(last_scale_up_at: nil, last_scale_down_at: nil)
      now = Time.current
      quoted_key = connection.quote(key)
      quoted_now = connection.quote(now)

      if last_scale_up_at
        quoted_time = connection.quote(last_scale_up_at)
        connection.execute(<<~SQL)
          INSERT INTO #{TABLE_NAME} (key, last_scale_up_at, created_at, updated_at)
          VALUES (#{quoted_key}, #{quoted_time}, #{quoted_now}, #{quoted_now})
          ON CONFLICT (key) DO UPDATE SET
            last_scale_up_at = EXCLUDED.last_scale_up_at,
            updated_at = EXCLUDED.updated_at
        SQL
      elsif last_scale_down_at
        quoted_time = connection.quote(last_scale_down_at)
        connection.execute(<<~SQL)
          INSERT INTO #{TABLE_NAME} (key, last_scale_down_at, created_at, updated_at)
          VALUES (#{quoted_key}, #{quoted_time}, #{quoted_now}, #{quoted_now})
          ON CONFLICT (key) DO UPDATE SET
            last_scale_down_at = EXCLUDED.last_scale_down_at,
            updated_at = EXCLUDED.updated_at
        SQL
      end
    end
  end
end
