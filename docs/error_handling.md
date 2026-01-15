# Error Handling Guide

## Error Hierarchy

```ruby
SolidQueueHerokuAutoscaler::Error (StandardError)
├── SolidQueueHerokuAutoscaler::ConfigurationError
├── SolidQueueHerokuAutoscaler::HerokuAPIError
├── SolidQueueHerokuAutoscaler::MetricsError
├── SolidQueueHerokuAutoscaler::LockError
└── SolidQueueHerokuAutoscaler::CooldownActiveError
```

## Error Types

### ConfigurationError

**When:** Configuration is invalid or missing required values.

**Examples:**
```ruby
# Missing required settings
SolidQueueHerokuAutoscaler.configure do |config|
  config.heroku_api_key = nil
end
# => ConfigurationError: heroku_api_key is required

# Invalid settings
SolidQueueHerokuAutoscaler.configure do |config|
  config.heroku_api_key = 'key'
  config.heroku_app_name = 'app'
  config.min_workers = 10
  config.max_workers = 5
end
# => ConfigurationError: min_workers cannot exceed max_workers
```

**How to handle:**
```ruby
begin
  SolidQueueHerokuAutoscaler.configure do |config|
    # ...
  end
rescue SolidQueueHerokuAutoscaler::ConfigurationError => e
  Rails.logger.error "Autoscaler configuration invalid: #{e.message}"
  # Decide whether to:
  # 1. Fall back to defaults
  # 2. Disable autoscaling
  # 3. Halt application startup
  raise
end
```

**Note:** The `AutoscaleJob` uses `discard_on ConfigurationError` because configuration errors won't self-heal with retries.

---

### HerokuAPIError

**When:** Heroku Platform API calls fail.

**Attributes:**
- `status_code` (Integer, nil): HTTP status code
- `response_body` (String, nil): Response body from Heroku

**Examples:**
```ruby
# Invalid API key
client.current_formation
# => HerokuAPIError: Failed to get formation info: Unauthorized (401)

# App not found
client.scale(5)
# => HerokuAPIError: Failed to scale worker to 5: App not found (404)

# Rate limited
client.scale(5)
# => HerokuAPIError: Failed to scale worker to 5: Rate limit exceeded (429)

# Server error
client.scale(5)
# => HerokuAPIError: Failed to scale worker to 5: Internal server error (500)
```

**How to handle:**
```ruby
begin
  SolidQueueHerokuAutoscaler.scale!
rescue SolidQueueHerokuAutoscaler::HerokuAPIError => e
  case e.status_code
  when 401
    Rails.logger.error "Invalid Heroku API key - check HEROKU_API_KEY"
    # Alert ops team
  when 404
    Rails.logger.error "Heroku app not found - check HEROKU_APP_NAME"
    # Alert ops team
  when 429
    Rails.logger.warn "Heroku rate limited - will retry later"
    # Normal - will succeed on next run
  when 500..599
    Rails.logger.warn "Heroku API error - will retry later"
    # Retry on next run
  else
    Rails.logger.error "Unexpected Heroku API error: #{e.message}"
    raise
  end
end
```

---

### MetricsError

**When:** Database queries for queue metrics fail.

**Examples:**
```ruby
# Database connection issue
metrics.collect
# => MetricsError: Failed to collect metrics: connection refused

# Missing table
metrics.queue_depth
# => MetricsError: relation "solid_queue_ready_executions" does not exist
```

**How to handle:**
```ruby
begin
  metrics = SolidQueueHerokuAutoscaler.metrics
rescue SolidQueueHerokuAutoscaler::MetricsError => e
  Rails.logger.error "Failed to collect queue metrics: #{e.message}"
  # Metrics errors are usually transient (DB connection issues)
  # or indicate missing Solid Queue setup
end
```

---

### LockError

**When:** PostgreSQL advisory lock operations fail.

**Examples:**
```ruby
# Lock already held by another instance
lock.acquire!
# => LockError: Could not acquire advisory lock 'solid_queue_autoscaler' (id: 123456789)

# Database connection lost
lock.try_lock
# => LockError: Failed to acquire lock: connection refused
```

**How to handle:**
```ruby
begin
  result = SolidQueueHerokuAutoscaler.scale!
rescue SolidQueueHerokuAutoscaler::LockError => e
  # This is expected when another autoscaler is running
  Rails.logger.debug "Another autoscaler instance is running: #{e.message}"
end

# Or use non-blocking approach (returns skipped result instead of raising)
result = SolidQueueHerokuAutoscaler.scale!
if result.skipped? && result.skipped_reason.include?('advisory lock')
  Rails.logger.debug "Another instance is handling scaling"
end
```

---

### CooldownActiveError

**When:** Scaling is blocked due to cooldown period (informational error, not raised by default).

**Attributes:**
- `remaining_seconds` (Float): Seconds until cooldown expires

**Examples:**
```ruby
# After a recent scale event
raise CooldownActiveError.new(45.3)
# => CooldownActiveError: Cooldown active, 45s remaining
```

**Note:** The scaler doesn't raise this error by default - it returns a skipped result. This error class is available if you want to implement custom logic.

```ruby
# Access cooldown info from result
result = SolidQueueHerokuAutoscaler.scale!
if result.skipped? && result.skipped_reason.include?('Cooldown')
  # Extract remaining time from message
  remaining = result.skipped_reason.match(/\((\d+)s remaining\)/)[1].to_i
  puts "Wait #{remaining} seconds before next scale"
end
```

---

## Comprehensive Error Handling

### Production Pattern

```ruby
class AutoscalerService
  MAX_RETRIES = 3

  def scale_with_retry
    retry_count = 0

    begin
      result = SolidQueueHerokuAutoscaler.scale!
      
      if result.success?
        log_success(result)
      else
        log_failure(result)
      end
      
      result

    rescue SolidQueueHerokuAutoscaler::ConfigurationError => e
      # Fatal - don't retry
      log_error("Configuration error", e)
      notify_ops_team(e)
      raise

    rescue SolidQueueHerokuAutoscaler::HerokuAPIError => e
      # Retry on server errors, fail fast on client errors
      if retryable_status?(e.status_code) && retry_count < MAX_RETRIES
        retry_count += 1
        sleep_time = 2 ** retry_count
        log_warn("Heroku API error, retrying in #{sleep_time}s", e)
        sleep(sleep_time)
        retry
      else
        log_error("Heroku API error", e)
        raise unless ignorable_status?(e.status_code)
      end

    rescue SolidQueueHerokuAutoscaler::MetricsError => e
      # Retry on connection issues
      if retry_count < MAX_RETRIES
        retry_count += 1
        sleep(1)
        retry
      else
        log_error("Metrics collection failed", e)
        raise
      end

    rescue SolidQueueHerokuAutoscaler::LockError => e
      # Normal - another instance is running
      log_debug("Lock not acquired", e)
      nil

    rescue StandardError => e
      log_error("Unexpected error", e)
      raise
    end
  end

  private

  def retryable_status?(status)
    return true if status.nil?  # Network error
    status >= 500 || status == 429
  end

  def ignorable_status?(status)
    status == 429  # Rate limit - will succeed on next run
  end

  def log_success(result)
    if result.scaled?
      Rails.logger.info "[Autoscaler] Scaled: #{result.decision.from} -> #{result.decision.to}"
    elsif result.skipped?
      Rails.logger.debug "[Autoscaler] Skipped: #{result.skipped_reason}"
    else
      Rails.logger.debug "[Autoscaler] No change: #{result.decision&.reason}"
    end
  end

  def log_failure(result)
    Rails.logger.error "[Autoscaler] Failed: #{result.error&.message}"
  end

  def log_error(msg, error)
    Rails.logger.error "[Autoscaler] #{msg}: #{error.class} - #{error.message}"
  end

  def log_warn(msg, error)
    Rails.logger.warn "[Autoscaler] #{msg}: #{error.class} - #{error.message}"
  end

  def log_debug(msg, error)
    Rails.logger.debug "[Autoscaler] #{msg}: #{error.message}"
  end

  def notify_ops_team(error)
    # Integrate with your alerting system
    # Sentry.capture_exception(error)
    # PagerDuty.trigger(error)
  end
end
```

### Background Job Pattern

```ruby
class AutoscaleJob < ApplicationJob
  queue_as :autoscaler
  
  # Don't retry configuration errors
  discard_on SolidQueueHerokuAutoscaler::ConfigurationError
  
  # Retry API errors with exponential backoff
  retry_on SolidQueueHerokuAutoscaler::HerokuAPIError,
           wait: :exponentially_longer,
           attempts: 3

  # Retry metrics errors briefly
  retry_on SolidQueueHerokuAutoscaler::MetricsError,
           wait: 5.seconds,
           attempts: 2

  # Don't retry lock errors (normal operation)
  discard_on SolidQueueHerokuAutoscaler::LockError

  def perform
    result = SolidQueueHerokuAutoscaler.scale!
    
    unless result.success?
      raise result.error if result.error
    end
  end
end
```

### Monitoring Integration

```ruby
# With Sentry
begin
  SolidQueueHerokuAutoscaler.scale!
rescue SolidQueueHerokuAutoscaler::Error => e
  Sentry.capture_exception(e, extra: {
    metrics: SolidQueueHerokuAutoscaler.metrics.to_h,
    config: {
      min_workers: SolidQueueHerokuAutoscaler.config.min_workers,
      max_workers: SolidQueueHerokuAutoscaler.config.max_workers,
      enabled: SolidQueueHerokuAutoscaler.config.enabled?
    }
  })
  raise
end

# With StatsD
class AutoscalerMetrics
  def self.track(&block)
    start = Time.now
    result = yield
    
    StatsD.histogram('autoscaler.duration', Time.now - start)
    StatsD.increment('autoscaler.success') if result.success?
    StatsD.increment('autoscaler.scaled') if result.scaled?
    StatsD.increment('autoscaler.skipped') if result.skipped?
    
    result
  rescue SolidQueueHerokuAutoscaler::Error => e
    StatsD.increment('autoscaler.error', tags: ["type:#{e.class.name.demodulize}"])
    raise
  end
end

AutoscalerMetrics.track { SolidQueueHerokuAutoscaler.scale! }
```

---

## Testing Error Scenarios

```ruby
RSpec.describe 'Error handling' do
  describe 'ConfigurationError' do
    it 'raises on missing API key' do
      expect {
        SolidQueueHerokuAutoscaler.configure do |config|
          config.heroku_api_key = nil
          config.heroku_app_name = 'test'
        end
      }.to raise_error(
        SolidQueueHerokuAutoscaler::ConfigurationError,
        /heroku_api_key is required/
      )
    end
  end

  describe 'HerokuAPIError' do
    let(:config) { configure_autoscaler }
    let(:client) { SolidQueueHerokuAutoscaler::HerokuClient.new(config: config) }

    it 'includes status code and body' do
      stub_heroku_error(status: 429, body: 'Rate limit exceeded')

      expect { client.scale(5) }.to raise_error(
        SolidQueueHerokuAutoscaler::HerokuAPIError
      ) do |error|
        expect(error.status_code).to eq(429)
        expect(error.response_body).to include('Rate limit')
      end
    end
  end

  describe 'LockError' do
    it 'raises when lock unavailable' do
      # Simulate another instance holding the lock
      lock1 = SolidQueueHerokuAutoscaler::AdvisoryLock.new
      lock1.acquire!

      lock2 = SolidQueueHerokuAutoscaler::AdvisoryLock.new
      expect { lock2.acquire! }.to raise_error(
        SolidQueueHerokuAutoscaler::LockError
      )
    ensure
      lock1&.release
    end
  end
end
```

---

## Error Quick Reference

| Error | Retry? | Action |
|-------|--------|--------|
| ConfigurationError | ❌ No | Fix configuration |
| HerokuAPIError (401) | ❌ No | Fix API key |
| HerokuAPIError (404) | ❌ No | Fix app name |
| HerokuAPIError (429) | ✅ Yes | Wait and retry |
| HerokuAPIError (5xx) | ✅ Yes | Wait and retry |
| MetricsError | ✅ Yes | Check DB connection |
| LockError | ❌ Skip | Normal - another instance running |
| CooldownActiveError | ❌ Skip | Wait for cooldown |
