# Configuration Guide

## Overview

The Solid Queue Heroku Autoscaler is configured via a Rails initializer. All settings have sensible defaults, but at minimum you must provide Heroku API credentials.

## Basic Configuration

Create an initializer at `config/initializers/solid_queue_autoscaler.rb`:

```ruby
SolidQueueAutoscaler.configure do |config|
  # Required: Heroku credentials
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
end
```

## Using the Install Generator

The gem includes a Rails generator to create the initializer:

```bash
rails generate solid_queue_autoscaler:install
```

This creates a fully-commented initializer with all available options.

## Environment Variables

The gem reads these environment variables by default:

| Variable | Description | Required |
|----------|-------------|----------|
| `HEROKU_API_KEY` | Heroku Platform API token | Yes |
| `HEROKU_APP_NAME` | Name of your Heroku app | Yes |

### Generating a Heroku API Key

```bash
# Create a dedicated authorization
heroku authorizations:create -d "Solid Queue Autoscaler"

# The token will be displayed - save it securely
# Example output:
# ID:          xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# Description: Solid Queue Autoscaler
# Scope:       global
# Token:       xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

For Heroku pipelines or CI, you can use the `HEROKU_API_KEY` environment variable which is automatically available.

## Complete Configuration Reference

```ruby
SolidQueueAutoscaler.configure do |config|
  # ============================================
  # REQUIRED: Heroku Settings
  # ============================================
  
  # Heroku Platform API OAuth token
  # Get one with: heroku authorizations:create -d "Solid Queue Autoscaler"
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  
  # Your Heroku app name (from dashboard URL)
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  
  # Process type to scale (must match Procfile)
  # Default: 'worker'
  config.process_type = 'worker'
  
  # ============================================
  # Worker Limits
  # ============================================
  
  # Minimum workers to maintain (never scale below this)
  # Default: 1
  config.min_workers = 1
  
  # Maximum workers allowed (never scale above this)
  # Default: 10
  config.max_workers = 10
  
  # ============================================
  # Scaling Strategy
  # ============================================
  
  # Choose how workers are added/removed:
  # :fixed - adds/removes fixed increment/decrement (default, backward compatible)
  # :proportional - calculates workers based on jobs/latency over threshold
  # :step_function - uses step thresholds (future)
  # Default: :fixed
  config.scaling_strategy = :fixed
  
  # ============================================
  # Scale-Up Thresholds
  # Triggers when ANY condition is met
  # ============================================
  
  # Scale up when queue depth reaches this level
  # Default: 100 jobs
  config.scale_up_queue_depth = 100
  
  # Scale up when oldest job age exceeds this (seconds)
  # Default: 300 (5 minutes)
  config.scale_up_latency_seconds = 300
  
  # Number of workers to add per scale-up event (used by :fixed strategy)
  # Default: 1
  config.scale_up_increment = 1
  
  # ============================================
  # Proportional Scaling Settings
  # Used when scaling_strategy is :proportional
  # ============================================
  
  # Add 1 worker for every N jobs over scale_up_queue_depth threshold
  # Example: With 50, if queue has 250 jobs over threshold, add 5 workers
  # Default: 50
  config.scale_up_jobs_per_worker = 50
  
  # Add 1 worker for every N seconds over scale_up_latency_seconds threshold
  # Example: With 60, if latency is 180s over threshold, add 3 workers
  # Default: 60
  config.scale_up_latency_per_worker = 60
  
  # Remove 1 worker for every N jobs under capacity
  # Default: 50
  config.scale_down_jobs_per_worker = 50
  
  # ============================================
  # Scale-Down Thresholds
  # Triggers when ALL conditions are met (or queue is idle)
  # ============================================
  
  # Scale down when queue depth is at or below this level
  # Default: 10 jobs
  config.scale_down_queue_depth = 10
  
  # Scale down when oldest job age is at or below this (seconds)
  # Default: 30 seconds
  config.scale_down_latency_seconds = 30
  
  # Minutes of idle time before considering scale down
  # Default: 5 minutes
  config.scale_down_idle_minutes = 5
  
  # Number of workers to remove per scale-down event
  # Default: 1
  config.scale_down_decrement = 1
  
  # ============================================
  # Cooldown Settings
  # Prevents rapid scaling oscillation
  # ============================================
  
  # Default cooldown period for both scale up and down (seconds)
  # Default: 120 (2 minutes)
  config.cooldown_seconds = 120
  
  # Override cooldown specifically for scale-up events
  # Default: nil (uses cooldown_seconds)
  config.scale_up_cooldown_seconds = 60
  
  # Override cooldown specifically for scale-down events
  # Default: nil (uses cooldown_seconds)
  config.scale_down_cooldown_seconds = 180
  
  # ============================================
  # Advisory Lock Settings
  # Ensures only one autoscaler runs at a time
  # ============================================
  
  # Timeout for lock acquisition (seconds)
  # Default: 30
  config.lock_timeout_seconds = 30
  
  # Lock key name (should be unique per app)
  # Default: 'solid_queue_autoscaler'
  config.lock_key = 'solid_queue_autoscaler'
  
  # ============================================
  # Behavior Settings
  # ============================================
  
  # Dry run mode - logs decisions without executing
  # Default: false
  config.dry_run = false
  
  # Master enable switch
  # Default: true
  config.enabled = true
  
  # Logger instance
  # Default: Rails.logger (or stdout if Rails not available)
  config.logger = Rails.logger
  
  # Persist cooldowns to database (survives dyno restarts)
  # Requires migration: rails generate solid_queue_autoscaler:migration
  # Default: true
  config.persist_cooldowns = true
  
  # ============================================
  # Queue Filtering
  # ============================================
  
  # Only consider specific queues for metrics
  # Default: nil (all queues)
  config.queues = ['default', 'mailers', 'critical']
  
  # ============================================
  # Database Connection
  # ============================================
  
  # Custom database connection for metrics queries
  # Default: nil (uses ActiveRecord::Base.connection)
  config.database_connection = nil
  
  # Solid Queue table name prefix
  # Must end with an underscore (e.g., 'solid_queue_', 'my_app_queue_')
  # Default: 'solid_queue_'
  config.table_prefix = 'solid_queue_'
  
  # ============================================
  # Infrastructure Adapter
  # ============================================
  
  # Adapter class for scaling (default: Heroku)
  # See docs/adapters.md for creating custom adapters
  # config.adapter_class = SolidQueueAutoscaler::Adapters::Heroku
  
  # Or set a pre-configured adapter instance
  # config.adapter = MyCustomAdapter.new(config: config)
end
```

## Scaling Strategies

### Fixed Strategy (Default)

The fixed strategy adds or removes a constant number of workers per scaling event. This is the simplest and most predictable approach.

```ruby
SolidQueueAutoscaler.configure do |config|
  config.scaling_strategy = :fixed
  config.scale_up_increment = 1    # Add 1 worker when scaling up
  config.scale_down_decrement = 1  # Remove 1 worker when scaling down
  # ...
end
```

**Best for:**
- Predictable, gradual scaling
- When you want tight control over scaling speed
- Workloads with relatively stable patterns

### Proportional Strategy

The proportional strategy calculates the number of workers to add based on how far over the thresholds your metrics are. This allows faster response to large load spikes.

```ruby
SolidQueueAutoscaler.configure do |config|
  config.scaling_strategy = :proportional
  
  # Base thresholds (same as fixed)
  config.scale_up_queue_depth = 100
  config.scale_up_latency_seconds = 300
  
  # Proportional settings
  config.scale_up_jobs_per_worker = 50      # Add 1 worker per 50 jobs over threshold
  config.scale_up_latency_per_worker = 60   # Add 1 worker per 60s latency over threshold
  config.scale_down_jobs_per_worker = 50    # Remove 1 worker per 50 jobs under capacity
  # ...
end
```

**How it works:**

1. **Scale Up Calculation:**
   ```
   jobs_over = queue_depth - scale_up_queue_depth
   workers_for_jobs = ceil(jobs_over / scale_up_jobs_per_worker)
   
   latency_over = latency - scale_up_latency_seconds  
   workers_for_latency = ceil(latency_over / scale_up_latency_per_worker)
   
   workers_to_add = max(workers_for_jobs, workers_for_latency)
   ```

2. **Example:**
   - Queue depth: 350 jobs (threshold: 100)
   - Jobs over threshold: 250
   - scale_up_jobs_per_worker: 50
   - Workers to add: ceil(250/50) = 5 workers

**Best for:**
- Workloads with variable load spikes
- When fast response to large backlogs is important
- Cost-sensitive deployments that want aggressive scale-down

### Comparing Strategies

| Scenario | Fixed (+1) | Proportional (50 jobs/worker) |
|----------|------------|-------------------------------|
| 150 jobs over threshold | +1 worker | +3 workers |
| 300 jobs over threshold | +1 worker | +6 workers |
| 25 jobs over threshold | +1 worker | +1 worker |

## Configuration Patterns

### Production Configuration

```ruby
# config/initializers/solid_queue_autoscaler.rb
SolidQueueAutoscaler.configure do |config|
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  
  # Conservative settings for production
  config.min_workers = 2              # Always have redundancy
  config.max_workers = 20             # Cap costs
  
  # Scale up quickly on high load
  config.scale_up_queue_depth = 50
  config.scale_up_latency_seconds = 120  # 2 minutes
  config.scale_up_cooldown_seconds = 60  # Quick to respond
  
  # Scale down slowly to avoid flapping
  config.scale_down_queue_depth = 5
  config.scale_down_latency_seconds = 15
  config.scale_down_cooldown_seconds = 300  # 5 minutes
  
  # Production enabled
  config.enabled = Rails.env.production?
  config.dry_run = false
end
```

### Development Configuration

```ruby
# config/initializers/solid_queue_autoscaler.rb
SolidQueueAutoscaler.configure do |config|
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  
  # Safe settings for development
  config.min_workers = 1
  config.max_workers = 2
  
  # More aggressive thresholds for testing
  config.scale_up_queue_depth = 10
  config.scale_up_latency_seconds = 30
  config.cooldown_seconds = 30
  
  # Dry run in development
  config.dry_run = true
  config.enabled = true
end
```

### Staging Configuration

```ruby
# config/initializers/solid_queue_autoscaler.rb
SolidQueueAutoscaler.configure do |config|
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  
  # Moderate settings for staging
  config.min_workers = 1
  config.max_workers = 5
  
  config.scale_up_queue_depth = 25
  config.scale_up_latency_seconds = 60
  
  # Enable with dry run to test decisions
  config.enabled = true
  config.dry_run = ENV['AUTOSCALER_DRY_RUN'] == 'true'
end
```

### Multi-Queue Configuration

```ruby
# config/initializers/solid_queue_autoscaler.rb
SolidQueueAutoscaler.configure do |config|
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  
  # Only scale based on specific queues
  # Ignores queues like 'autoscaler' that shouldn't affect scaling
  config.queues = ['default', 'mailers', 'critical', 'webhooks']
  
  # Different process type if you have multiple worker types
  config.process_type = 'worker'  # or 'critical_worker', etc.
end
```

### Environment-Based Configuration

```ruby
# config/initializers/solid_queue_autoscaler.rb
SolidQueueAutoscaler.configure do |config|
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  
  case Rails.env
  when 'production'
    config.min_workers = 2
    config.max_workers = 20
    config.enabled = true
    config.dry_run = false
  when 'staging'
    config.min_workers = 1
    config.max_workers = 5
    config.enabled = true
    config.dry_run = ENV['AUTOSCALER_DRY_RUN'] != 'false'
  else
    config.min_workers = 1
    config.max_workers = 2
    config.enabled = false
  end
end
```

## Queue Configuration for Autoscaler Job

The autoscaler runs as a Solid Queue job. Configure it with a dedicated queue:

### Recurring Job Configuration

```yaml
# config/recurring.yml
autoscaler:
  class: SolidQueueAutoscaler::AutoscaleJob
  queue: autoscaler
  schedule: every 30 seconds
```

### Queue Configuration

```yaml
# config/queue.yml
queues:
  - autoscaler    # Dedicated queue for autoscaler
  - critical      # High-priority business jobs
  - default       # Standard jobs
  - mailers       # Email jobs

workers:
  # Autoscaler gets its own worker thread
  - queues: [autoscaler]
    threads: 1
  
  # Business queues get more threads
  - queues: [critical, default, mailers]
    threads: 5
```

### Why a Dedicated Queue?

1. **Isolation**: Autoscaler jobs won't compete with business jobs
2. **Predictability**: Guaranteed to run even under high load
3. **Control**: Easy to pause/resume autoscaling independently

## Validation

The configuration is validated when you call `configure`:

```ruby
SolidQueueAutoscaler.configure do |config|
  config.min_workers = 10
  config.max_workers = 5  # Error! min > max
end
# => SolidQueueAutoscaler::ConfigurationError: 
#    min_workers cannot exceed max_workers
```

### Validation Rules

| Setting | Rule |
|---------|------|
| `heroku_api_key` | Required, non-empty |
| `heroku_app_name` | Required, non-empty |
| `process_type` | Required, non-empty |
| `min_workers` | Must be >= 0 |
| `max_workers` | Must be > 0 |
| `min_workers` | Cannot exceed `max_workers` |
| `scale_up_queue_depth` | Must be > 0 |
| `scale_up_latency_seconds` | Must be > 0 |
| `scale_up_increment` | Must be > 0 |
| `scale_down_queue_depth` | Must be >= 0 |
| `scale_down_decrement` | Must be > 0 |
| `cooldown_seconds` | Must be >= 0 |
| `lock_timeout_seconds` | Must be > 0 |
| `table_prefix` | Must end with an underscore |
| `scaling_strategy` | Must be `:fixed` or `:proportional` |

## Runtime Configuration Changes

Configuration is read at startup. To change settings at runtime:

```ruby
# Reset and reconfigure (not recommended in production)
SolidQueueAutoscaler.reset_configuration!
SolidQueueAutoscaler.configure do |config|
  # new settings
end

# Better: use enable/disable for quick changes
SolidQueueAutoscaler.config.enabled = false  # Pause autoscaling
SolidQueueAutoscaler.config.dry_run = true   # Enter dry-run mode
```

## Debugging Configuration

```ruby
# In Rails console
config = SolidQueueAutoscaler.config

# Check current settings
puts config.max_workers
puts config.scale_up_queue_depth
puts config.dry_run?
puts config.enabled?

# Check effective cooldowns
puts config.effective_scale_up_cooldown
puts config.effective_scale_down_cooldown

# Verify Heroku connection
workers = SolidQueueAutoscaler.current_workers
puts "Current workers: #{workers}"

# Check metrics
metrics = SolidQueueAutoscaler.metrics
puts metrics.to_h
```

## Security Considerations

1. **Never commit API keys**: Use environment variables
2. **Use dedicated Heroku tokens**: Don't use your personal token
3. **Limit token scope**: Create app-specific authorizations
4. **Rotate tokens periodically**: Delete old authorizations

```bash
# List existing authorizations
heroku authorizations

# Delete old authorization
heroku authorizations:destroy <id>

# Create new one
heroku authorizations:create -d "Solid Queue Autoscaler $(date +%Y-%m)"
```
