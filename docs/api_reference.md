# API Reference

## Table of Contents

- [SolidQueueAutoscaler](#solidqueueherokuautoscaler)
- [Configuration](#configuration)
- [Adapters](#adapters)
- [Scaler](#scaler)
- [Metrics](#metrics)
- [DecisionEngine](#decisionengine)
- [AdvisoryLock](#advisorylock)
- [AutoscaleJob](#autoscalejob)
- [Error Classes](#error-classes)

## SolidQueueAutoscaler

The main module providing the public API.

### .configure

Configure the autoscaler with a block.

```ruby
SolidQueueAutoscaler.configure do |config|
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  # ... other options
end
```

**Yields:** `Configuration` object

**Returns:** `Configuration` object (validated)

**Raises:** `ConfigurationError` if validation fails

### .config

Access the current configuration.

```ruby
config = SolidQueueAutoscaler.config
puts config.max_workers  # => 10
```

**Returns:** `Configuration` object

### .scale!

Execute the autoscaler once.

```ruby
result = SolidQueueAutoscaler.scale!

if result.success?
  if result.scaled?
    puts "Scaled from #{result.decision.from} to #{result.decision.to}"
  else
    puts "No change: #{result.decision&.reason}"
  end
else
  puts "Error: #{result.error}"
end
```

**Returns:** `Scaler::ScaleResult` struct

### .metrics

Collect current queue metrics.

```ruby
metrics = SolidQueueAutoscaler.metrics

puts "Queue depth: #{metrics.queue_depth}"
puts "Latency: #{metrics.oldest_job_age_seconds}s"
puts "Jobs/min: #{metrics.jobs_per_minute}"
puts "Active workers: #{metrics.active_workers}"
puts "Queues: #{metrics.queues_breakdown}"
```

**Returns:** `Metrics::Result` struct

### .current_workers

Get current worker count from Heroku.

```ruby
count = SolidQueueAutoscaler.current_workers
puts "Currently running: #{count} workers"
```

**Returns:** `Integer`

**Raises:** `HerokuAPIError` if API call fails

### .reset_configuration!

Reset configuration to nil (mainly for testing).

```ruby
SolidQueueAutoscaler.reset_configuration!
```

---

## Configuration

Configuration object for the autoscaler.

### Heroku Settings

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `heroku_api_key` | String | `ENV['HEROKU_API_KEY']` | Heroku OAuth token |
| `heroku_app_name` | String | `ENV['HEROKU_APP_NAME']` | Target Heroku app name |
| `process_type` | String | `'worker'` | Dyno process type to scale |

### Worker Limits

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `min_workers` | Integer | `1` | Minimum worker count |
| `max_workers` | Integer | `10` | Maximum worker count |

### Scaling Strategy

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `scaling_strategy` | Symbol | `:fixed` | Strategy for calculating scale amount (`:fixed`, `:proportional`, `:step_function`) |

### Scale-Up Thresholds

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `scale_up_queue_depth` | Integer | `100` | Queue depth to trigger scale up |
| `scale_up_latency_seconds` | Integer | `300` | Latency (seconds) to trigger scale up |
| `scale_up_increment` | Integer | `1` | Workers to add per scale event (fixed strategy) |

### Proportional Scaling Settings

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `scale_up_jobs_per_worker` | Integer | `50` | Jobs over threshold per additional worker |
| `scale_up_latency_per_worker` | Integer | `60` | Seconds over threshold per additional worker |
| `scale_down_jobs_per_worker` | Integer | `50` | Jobs under capacity per worker to remove |

### Scale-Down Thresholds

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `scale_down_queue_depth` | Integer | `10` | Queue depth threshold for scale down |
| `scale_down_latency_seconds` | Integer | `30` | Latency threshold for scale down |
| `scale_down_idle_minutes` | Integer | `5` | Minutes idle before scaling down |
| `scale_down_decrement` | Integer | `1` | Workers to remove per scale event |

### Cooldown Settings

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `cooldown_seconds` | Integer | `120` | Default cooldown period |
| `scale_up_cooldown_seconds` | Integer | `nil` | Override for scale up cooldown |
| `scale_down_cooldown_seconds` | Integer | `nil` | Override for scale down cooldown |

### Advisory Lock Settings

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `lock_timeout_seconds` | Integer | `30` | Lock acquisition timeout |
| `lock_key` | String | `'solid_queue_autoscaler'` | Advisory lock key name |

### Behavior Settings

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `dry_run` | Boolean | `false` | Log without executing |
| `enabled` | Boolean | `true` | Master enable switch |
| `logger` | Logger | `Rails.logger` | Logger instance |

### Queue Filtering

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `queues` | Array | `nil` | Filter to specific queues (nil = all) |

### Database Connection

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `database_connection` | Connection | `nil` | Custom DB connection (defaults to ActiveRecord::Base.connection) |
| `table_prefix` | String | `'solid_queue_'` | Solid Queue table name prefix (must end with underscore) |

### Adapter Settings

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `adapter_class` | Class | `nil` | Adapter class to use (defaults to Heroku) |
| `adapter` | Adapters::Base | auto | Adapter instance (auto-created from adapter_class) |

### Methods

#### #validate!

Validate the configuration.

```ruby
config = SolidQueueAutoscaler::Configuration.new
config.heroku_api_key = 'test'
config.heroku_app_name = 'my-app'
config.validate!  # => true
```

**Returns:** `true` if valid

**Raises:** `ConfigurationError` with validation errors

#### #effective_scale_up_cooldown

Get effective scale up cooldown.

```ruby
config.effective_scale_up_cooldown
# => scale_up_cooldown_seconds || cooldown_seconds
```

**Returns:** `Integer` seconds

#### #effective_scale_down_cooldown

Get effective scale down cooldown.

```ruby
config.effective_scale_down_cooldown
# => scale_down_cooldown_seconds || cooldown_seconds
```

**Returns:** `Integer` seconds

#### #connection

Get database connection.

```ruby
config.connection
# => database_connection || ActiveRecord::Base.connection
```

**Returns:** Database connection object

#### #dry_run?

Check if dry run mode is enabled.

```ruby
config.dry_run?  # => true/false
```

**Returns:** `Boolean`

#### #enabled?

Check if autoscaler is enabled.

```ruby
config.enabled?  # => true/false
```

**Returns:** `Boolean`

---

## Adapters

Adapters provide the interface to different infrastructure platforms.

### Adapters::Base

Base class for all adapters. Subclass this to create custom adapters.

#### Constructor

```ruby
adapter = SolidQueueAutoscaler::Adapters::Base.new(config: config)
```

**Parameters:**
- `config` (Configuration): Configuration object

#### #current_workers

Get current worker count.

```ruby
adapter.current_workers
# => 3
```

**Returns:** `Integer`

**Raises:** `NotImplementedError` in base class

#### #scale

Scale to specified quantity.

```ruby
adapter.scale(5)
# => 5
```

**Parameters:**
- `quantity` (Integer): Target worker count

**Returns:** `Integer` new worker count

**Raises:** `NotImplementedError` in base class

#### #name

Get adapter name for logging.

```ruby
adapter.name
# => "Heroku"
```

**Returns:** `String`

#### #configured?

Check if adapter is properly configured.

```ruby
adapter.configured?
# => true
```

**Returns:** `Boolean`

#### #configuration_errors

Get configuration validation errors.

```ruby
adapter.configuration_errors
# => ["heroku_api_key is required"]
```

**Returns:** `Array<String>`

### Adapters::Heroku

Heroku adapter using Platform API.

```ruby
# Used by default when no adapter is specified
adapter = SolidQueueAutoscaler::Adapters::Heroku.new(config: config)

adapter.current_workers  # => 3
adapter.scale(5)         # => 5
adapter.name             # => "Heroku"
adapter.formation_list   # => [{"type" => "worker", "quantity" => 3, ...}]
```

**Additional Methods:**

- `formation_list` - List all formations for the app

### Adapters Module Methods

```ruby
# Get all built-in adapters
SolidQueueAutoscaler::Adapters.all
# => [SolidQueueAutoscaler::Adapters::Heroku]

# Find adapter by name
SolidQueueAutoscaler::Adapters.find(:heroku)
# => SolidQueueAutoscaler::Adapters::Heroku
```

### Creating Custom Adapters

See the [Adapters Guide](adapters.md) for detailed instructions on creating custom adapters.

```ruby
class MyAdapter < SolidQueueAutoscaler::Adapters::Base
  def current_workers
    # Implementation
  end

  def scale(quantity)
    # Implementation
  end

  def name
    'My Platform'
  end
end

# Use it
SolidQueueAutoscaler.configure do |config|
  config.adapter_class = MyAdapter
end
```

---

## Scaler

Main orchestrator that coordinates metrics collection, decision making, and scaling.

### Constructor

```ruby
scaler = SolidQueueAutoscaler::Scaler.new(config: nil)
```

**Parameters:**
- `config` (Configuration, optional): Custom configuration

### #run

Execute scaling with advisory lock (non-blocking).

```ruby
result = scaler.run
```

**Returns:** `ScaleResult` struct

If lock cannot be acquired, returns skipped result instead of blocking.

### #run!

Execute scaling with advisory lock (blocking).

```ruby
result = scaler.run!
```

**Returns:** `ScaleResult` struct

**Raises:** `LockError` if lock cannot be acquired

### ScaleResult

Struct returned by scaling operations.

```ruby
result = scaler.run

# Check success
result.success?      # => true/false

# Check if scaling occurred
result.scaled?       # => true/false

# Check if skipped
result.skipped?      # => true/false
result.skipped_reason  # => "Cooldown active (30s remaining)"

# Access decision
result.decision.action    # => :scale_up, :scale_down, :no_change
result.decision.from      # => 2
result.decision.to        # => 3
result.decision.reason    # => "queue_depth=150 >= 100"
result.decision.delta     # => 1

# Access metrics
result.metrics.queue_depth
result.metrics.oldest_job_age_seconds

# Access error (if failed)
result.error  # => Exception or nil

# Timestamp
result.executed_at  # => Time
```

### Class Methods

#### .reset_cooldowns!

Reset cooldown timestamps (for testing).

```ruby
SolidQueueAutoscaler::Scaler.reset_cooldowns!
```

---

## Metrics

Collects queue metrics from Solid Queue PostgreSQL tables.

### Constructor

```ruby
metrics = SolidQueueAutoscaler::Metrics.new(config: nil)
```

**Parameters:**
- `config` (Configuration, optional): Custom configuration

### #collect

Collect all metrics.

```ruby
result = metrics.collect

result.queue_depth              # => 42
result.oldest_job_age_seconds   # => 15.3
result.jobs_per_minute          # => 100
result.claimed_jobs             # => 5
result.failed_jobs              # => 0
result.blocked_jobs             # => 2
result.active_workers           # => 3
result.queues_breakdown         # => {"default" => 30, "mailers" => 12}
result.collected_at             # => Time
```

**Returns:** `Metrics::Result` struct

### Individual Metric Methods

```ruby
metrics.queue_depth           # Count of ready executions
metrics.oldest_job_age_seconds  # Age of oldest pending job
metrics.jobs_per_minute       # Completed jobs in last minute
metrics.claimed_jobs_count    # Currently claimed jobs
metrics.failed_jobs_count     # Failed executions
metrics.blocked_jobs_count    # Blocked executions
metrics.active_workers_count  # Workers with recent heartbeat
metrics.queues_breakdown      # Hash of queue => count
```

### Metrics::Result

Struct containing collected metrics.

```ruby
result = metrics.collect

# Check if queue is idle
result.idle?  # => true if queue_depth == 0 && claimed_jobs == 0

# Alias for oldest_job_age_seconds
result.latency_seconds

# Convert to hash
result.to_h  # => { queue_depth: 42, ... }
```

---

## DecisionEngine

Determines scaling decisions based on metrics and configuration.

### Constructor

```ruby
engine = SolidQueueAutoscaler::DecisionEngine.new(config: nil)
```

**Parameters:**
- `config` (Configuration, optional): Custom configuration

### #decide

Make a scaling decision.

```ruby
decision = engine.decide(
  metrics: metrics_result,
  current_workers: 3
)

decision.action    # => :scale_up, :scale_down, :no_change
decision.from      # => 3
decision.to        # => 4
decision.reason    # => "queue_depth=150 >= 100"

# Helpers
decision.scale_up?    # => true
decision.scale_down?  # => false
decision.no_change?   # => false
decision.delta        # => 1
```

**Parameters:**
- `metrics` (Metrics::Result): Collected metrics
- `current_workers` (Integer): Current worker count

**Returns:** `Decision` struct

### Decision Logic

**Scale Up** when ANY condition is met:
- `queue_depth >= scale_up_queue_depth`
- `oldest_job_age_seconds >= scale_up_latency_seconds`

**Scale Down** when ALL conditions are met:
- `queue_depth <= scale_down_queue_depth`
- `oldest_job_age_seconds <= scale_down_latency_seconds`
- OR `queue.idle?` (no pending or claimed jobs)

**No Change** when:
- Already at `min_workers` or `max_workers`
- Metrics within normal range

---

## HerokuClient

Wrapper for Heroku Platform API.

### Constructor

```ruby
client = SolidQueueAutoscaler::HerokuClient.new(config: nil)
```

**Parameters:**
- `config` (Configuration, optional): Custom configuration

### #current_formation

Get current dyno count.

```ruby
count = client.current_formation
# => 3
```

**Returns:** `Integer` quantity

**Raises:** `HerokuAPIError` if API call fails

### #scale

Scale to specified quantity.

```ruby
client.scale(5)  # Scale to 5 workers
```

**Parameters:**
- `quantity` (Integer): Target worker count

**Returns:** `Integer` new quantity

**Raises:** `HerokuAPIError` if API call fails

In dry-run mode, logs the action without making API call.

### #formation_list

List all formations for the app.

```ruby
formations = client.formation_list
formations.each do |f|
  puts "#{f['type']}: #{f['quantity']} dynos"
end
```

**Returns:** Array of formation hashes

**Raises:** `HerokuAPIError` if API call fails

---

## AdvisoryLock

PostgreSQL advisory lock wrapper for singleton execution.

### Constructor

```ruby
lock = SolidQueueAutoscaler::AdvisoryLock.new(
  lock_key: 'custom_key',
  timeout: 60
)
```

**Parameters:**
- `lock_key` (String, optional): Lock key (defaults to config.lock_key)
- `timeout` (Integer, optional): Lock timeout (defaults to config.lock_timeout_seconds)

### #with_lock

Execute block with lock held.

```ruby
lock.with_lock do
  # Critical section
  # Lock is automatically released after block
end
```

**Yields:** Block to execute

**Raises:** `LockError` if lock cannot be acquired

### #try_lock

Attempt to acquire lock (non-blocking).

```ruby
if lock.try_lock
  begin
    # Critical section
  ensure
    lock.release
  end
else
  puts "Another instance is running"
end
```

**Returns:** `Boolean` true if lock acquired

### #acquire!

Acquire lock (raises on failure).

```ruby
lock.acquire!  # Raises LockError if unavailable
```

**Returns:** `true` if acquired

**Raises:** `LockError` if lock cannot be acquired

### #release

Release the lock.

```ruby
lock.release
```

**Returns:** `true` if released, `false` if not held

### #locked?

Check if lock is currently held.

```ruby
lock.locked?  # => true/false
```

**Returns:** `Boolean`

---

## AutoscaleJob

ActiveJob for running autoscaler as a recurring task.

### Usage

```yaml
# config/recurring.yml
autoscaler:
  class: SolidQueueAutoscaler::AutoscaleJob
  queue: autoscaler
  schedule: every 30 seconds
```

```ruby
# Enqueue manually
SolidQueueAutoscaler::AutoscaleJob.perform_later
```

### Behavior

- Calls `SolidQueueAutoscaler.scale!`
- Logs success/failure/skip
- Discards jobs that fail due to `ConfigurationError` (won't retry)
- Re-raises other errors for retry

---

## Error Classes

### SolidQueueAutoscaler::Error

Base error class.

```ruby
rescue SolidQueueAutoscaler::Error => e
  # Catches all gem errors
end
```

### SolidQueueAutoscaler::ConfigurationError

Raised when configuration is invalid.

```ruby
begin
  SolidQueueAutoscaler.configure do |config|
    config.heroku_api_key = nil
  end
rescue SolidQueueAutoscaler::ConfigurationError => e
  puts e.message  # => "heroku_api_key is required"
end
```

### SolidQueueAutoscaler::HerokuAPIError

Raised when Heroku API calls fail.

```ruby
begin
  client.scale(5)
rescue SolidQueueAutoscaler::HerokuAPIError => e
  puts e.message
  puts e.status_code    # => 429
  puts e.response_body  # => "Rate limit exceeded"
end
```

**Attributes:**
- `status_code` (Integer, nil): HTTP status code
- `response_body` (String, nil): Response body

### SolidQueueAutoscaler::MetricsError

Raised when metrics collection fails.

```ruby
rescue SolidQueueAutoscaler::MetricsError => e
  puts "Failed to collect metrics: #{e.message}"
end
```

### SolidQueueAutoscaler::LockError

Raised when advisory lock operations fail.

```ruby
begin
  lock.acquire!
rescue SolidQueueAutoscaler::LockError => e
  puts "Another instance is running"
end
```

### SolidQueueAutoscaler::CooldownActiveError

Raised when cooldown is active (informational).

```ruby
rescue SolidQueueAutoscaler::CooldownActiveError => e
  puts e.remaining_seconds  # => 45.3
  puts e.message  # => "Cooldown active, 45s remaining"
end
```

**Attributes:**
- `remaining_seconds` (Float): Seconds until cooldown expires

---

## Rake Tasks

Available when using Rails:

```bash
# Scale once
bundle exec rake solid_queue_autoscaler:scale

# View current metrics
bundle exec rake solid_queue_autoscaler:metrics

# View current formation
bundle exec rake solid_queue_autoscaler:formation
```

### Example Output

```
$ rake solid_queue_autoscaler:metrics
Queue Metrics:
  Queue Depth: 42
  Oldest Job Age: 15s
  Jobs/Minute: 100
  Claimed Jobs: 5
  Failed Jobs: 0
  Blocked Jobs: 2
  Active Workers: 3
  Queues: {"default"=>30, "mailers"=>12}

$ rake solid_queue_autoscaler:formation
Current Formation:
  Process Type: worker
  Workers: 3
  Min: 1
  Max: 10
```
