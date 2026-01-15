# Solid Queue Heroku Autoscaler

[![CI](https://github.com/reillyse/solid_queue_heroku_autoscaler/actions/workflows/ci.yml/badge.svg)](https://github.com/reillyse/solid_queue_heroku_autoscaler/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/solid_queue_heroku_autoscaler.svg)](https://badge.fury.io/rb/solid_queue_heroku_autoscaler)

A control plane for [Solid Queue](https://github.com/rails/solid_queue) that automatically scales worker processes based on queue metrics. Supports both **Heroku** and **Kubernetes** deployments.

## Features

- **Metrics-based scaling**: Scales based on queue depth, job latency, and throughput
- **Multiple scaling strategies**: Fixed increment or proportional scaling based on load
- **Multi-worker support**: Configure and scale different worker types independently
- **Platform adapters**: Native support for Heroku and Kubernetes
- **Singleton execution**: Uses PostgreSQL advisory locks to ensure only one autoscaler runs at a time
- **Safety features**: Cooldowns, min/max limits, dry-run mode
- **Rails integration**: Configuration via initializer, Railtie with rake tasks
- **Flexible execution**: Run as a recurring Solid Queue job or standalone

## Installation

Add to your Gemfile:

```ruby
gem 'solid_queue_heroku_autoscaler'
```

Then run:

```bash
bundle install
```

### Database Setup (Recommended)

For persistent cooldown tracking that survives process restarts:

```bash
rails generate solid_queue_heroku_autoscaler:migration
rails db:migrate
```

This creates a `solid_queue_autoscaler_state` table to store cooldown timestamps.

### Dashboard Setup (Optional)

For a web UI to monitor autoscaler events and status:

```bash
rails generate solid_queue_heroku_autoscaler:dashboard
rails db:migrate
```

Then mount the dashboard in `config/routes.rb`:

```ruby
# With authentication (recommended)
authenticate :user, ->(u) { u.admin? } do
  mount SolidQueueHerokuAutoscaler::Dashboard::Engine => "/autoscaler"
end

# Or without authentication
mount SolidQueueHerokuAutoscaler::Dashboard::Engine => "/autoscaler"
```

## Quick Start

### Basic Configuration (Single Worker)

Create an initializer at `config/initializers/solid_queue_autoscaler.rb`:

```ruby
SolidQueueHerokuAutoscaler.configure do |config|
  # Platform: Heroku
  config.adapter = :heroku
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  config.process_type = 'worker'

  # Worker limits
  config.min_workers = 1
  config.max_workers = 10

  # Scaling thresholds
  config.scale_up_queue_depth = 100
  config.scale_up_latency_seconds = 300
  config.scale_down_queue_depth = 10
  config.scale_down_latency_seconds = 30
end
```

### Multi-Worker Configuration

Scale different worker types independently with named configurations:

```ruby
# Critical jobs worker - fast response, dedicated queue
SolidQueueHerokuAutoscaler.configure(:critical_worker) do |config|
  config.adapter = :heroku
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  config.process_type = 'critical_worker'
  
  # Only monitor the critical queue
  config.queues = ['critical']
  
  # Aggressive scaling for critical jobs
  config.min_workers = 2
  config.max_workers = 20
  config.scale_up_queue_depth = 10
  config.scale_up_latency_seconds = 30
  config.cooldown_seconds = 60
end

# Default worker - handles standard queues
SolidQueueHerokuAutoscaler.configure(:default_worker) do |config|
  config.adapter = :heroku
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  config.process_type = 'worker'
  
  # Monitor default and mailers queues
  config.queues = ['default', 'mailers']
  
  # Conservative scaling for background jobs
  config.min_workers = 1
  config.max_workers = 10
  config.scale_up_queue_depth = 100
  config.scale_up_latency_seconds = 300
  config.cooldown_seconds = 120
end

# Batch processing worker - handles long-running jobs
SolidQueueHerokuAutoscaler.configure(:batch_worker) do |config|
  config.adapter = :heroku
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  config.process_type = 'batch_worker'
  
  config.queues = ['batch', 'imports', 'exports']
  
  config.min_workers = 0
  config.max_workers = 5
  config.scale_up_queue_depth = 1  # Scale up when any batch job is queued
  config.scale_down_queue_depth = 0
  config.cooldown_seconds = 300
end
```

## Platform Adapters

### Heroku Adapter (Default)

```ruby
SolidQueueHerokuAutoscaler.configure do |config|
  config.adapter = :heroku
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  config.process_type = 'worker'  # Dyno type to scale
end
```

Generate a Heroku API key:

```bash
heroku authorizations:create -d "Solid Queue Autoscaler"
```

### Kubernetes Adapter

```ruby
SolidQueueHerokuAutoscaler.configure do |config|
  config.adapter = :kubernetes
  config.kubernetes_namespace = ENV.fetch('KUBERNETES_NAMESPACE', 'default')
  config.kubernetes_deployment = 'solid-queue-worker'
  
  # Optional: Custom kubeconfig path (defaults to in-cluster config)
  # config.kubernetes_config_path = '/path/to/kubeconfig'
end
```

The Kubernetes adapter uses the official `kubeclient` gem and supports:
- In-cluster service account authentication (recommended for production)
- External kubeconfig file authentication (useful for development)

## Configuration Reference

### Core Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `adapter` | Symbol | `:heroku` | Platform adapter (`:heroku` or `:kubernetes`) |
| `enabled` | Boolean | `true` | Master switch to enable/disable autoscaling |
| `dry_run` | Boolean | `false` | Log decisions without making changes |
| `queues` | Array | `nil` | Queue names to monitor (nil = all queues) |
| `table_prefix` | String | `'solid_queue_'` | Solid Queue table name prefix |

### Worker Limits

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `min_workers` | Integer | `1` | Minimum workers to maintain |
| `max_workers` | Integer | `10` | Maximum workers allowed |

### Scale-Up Thresholds

Scaling up triggers when **ANY** threshold is exceeded:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `scale_up_queue_depth` | Integer | `100` | Jobs in queue to trigger scale up |
| `scale_up_latency_seconds` | Integer | `300` | Oldest job age to trigger scale up |
| `scale_up_increment` | Integer | `1` | Workers to add (fixed strategy) |

### Scale-Down Thresholds

Scaling down triggers when **ALL** thresholds are met:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `scale_down_queue_depth` | Integer | `10` | Jobs in queue threshold |
| `scale_down_latency_seconds` | Integer | `30` | Oldest job age threshold |
| `scale_down_decrement` | Integer | `1` | Workers to remove |

### Scaling Strategies

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `scaling_strategy` | Symbol | `:fixed` | `:fixed` or `:proportional` |
| `scale_up_jobs_per_worker` | Integer | `50` | Jobs per worker (proportional) |
| `scale_up_latency_per_worker` | Integer | `60` | Seconds per worker (proportional) |
| `scale_down_jobs_per_worker` | Integer | `50` | Jobs capacity per worker |

### Cooldowns

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cooldown_seconds` | Integer | `120` | Default cooldown for both directions |
| `scale_up_cooldown_seconds` | Integer | `nil` | Override for scale-up cooldown |
| `scale_down_cooldown_seconds` | Integer | `nil` | Override for scale-down cooldown |
| `persist_cooldowns` | Boolean | `true` | Save cooldowns to database |

### Heroku-Specific

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `heroku_api_key` | String | `nil` | Heroku Platform API token |
| `heroku_app_name` | String | `nil` | Heroku app name |
| `process_type` | String | `'worker'` | Dyno type to scale |

### Kubernetes-Specific

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `kubernetes_namespace` | String | `'default'` | Kubernetes namespace |
| `kubernetes_deployment` | String | `nil` | Deployment name to scale |
| `kubernetes_config_path` | String | `nil` | Path to kubeconfig (optional) |

## Usage

### Running as a Solid Queue Recurring Job (Recommended)

Add to your `config/recurring.yml`:

```yaml
# Single worker configuration
autoscaler:
  class: SolidQueueHerokuAutoscaler::AutoscaleJob
  queue: autoscaler
  schedule: every 30 seconds

# Or for multi-worker: scale all workers
autoscaler_all:
  class: SolidQueueHerokuAutoscaler::AutoscaleJob
  queue: autoscaler
  schedule: every 30 seconds
  args: [:all]

# Or scale specific worker types on different schedules
autoscaler_critical:
  class: SolidQueueHerokuAutoscaler::AutoscaleJob
  queue: autoscaler
  schedule: every 15 seconds
  args: [:critical_worker]

autoscaler_default:
  class: SolidQueueHerokuAutoscaler::AutoscaleJob
  queue: autoscaler
  schedule: every 60 seconds
  args: [:default_worker]
```

### Running via Rake Tasks

```bash
# Scale the default worker
bundle exec rake solid_queue_autoscaler:scale

# Scale a specific worker type
WORKER=critical_worker bundle exec rake solid_queue_autoscaler:scale

# Scale all configured workers
bundle exec rake solid_queue_autoscaler:scale_all

# List all registered worker configurations
bundle exec rake solid_queue_autoscaler:workers

# View metrics for default worker
bundle exec rake solid_queue_autoscaler:metrics

# View metrics for specific worker
WORKER=critical_worker bundle exec rake solid_queue_autoscaler:metrics

# View current formation
bundle exec rake solid_queue_autoscaler:formation

# Check cooldown status
bundle exec rake solid_queue_autoscaler:cooldown

# Reset cooldowns
bundle exec rake solid_queue_autoscaler:reset_cooldown
```

### Running Programmatically

```ruby
# Scale the default worker
result = SolidQueueHerokuAutoscaler.scale!

# Scale a specific worker type
result = SolidQueueHerokuAutoscaler.scale!(:critical_worker)

# Scale all configured workers
results = SolidQueueHerokuAutoscaler.scale_all!

# Get metrics for a specific worker
metrics = SolidQueueHerokuAutoscaler.metrics(:critical_worker)
puts "Queue depth: #{metrics.queue_depth}"
puts "Latency: #{metrics.oldest_job_age_seconds}s"

# Get current worker count
workers = SolidQueueHerokuAutoscaler.current_workers(:default_worker)
puts "Current workers: #{workers}"

# List all registered workers
SolidQueueHerokuAutoscaler.registered_workers
# => [:critical_worker, :default_worker, :batch_worker]

# Get configuration for a specific worker
config = SolidQueueHerokuAutoscaler.config(:critical_worker)
```

## How It Works

### Metrics Collection

The autoscaler queries Solid Queue's PostgreSQL tables to collect:

- **Queue depth**: Count of jobs in `solid_queue_ready_executions`
- **Oldest job age**: Time since oldest job was enqueued (latency)
- **Throughput**: Jobs completed in the last minute
- **Active workers**: Workers with recent heartbeats
- **Per-queue breakdown**: Job counts by queue name

When `queues` is configured, metrics are filtered to only those queues.

### Decision Logic

**Scale Up** when ANY of these conditions are met:
- Queue depth >= `scale_up_queue_depth`
- Oldest job age >= `scale_up_latency_seconds`

**Scale Down** when ALL of these conditions are met:
- Queue depth <= `scale_down_queue_depth`
- Oldest job age <= `scale_down_latency_seconds`
- OR queue is completely idle (no pending or claimed jobs)

**No Change** when:
- Already at min/max workers
- Within cooldown period
- Metrics are in normal range

### Scaling Strategies

**Fixed Strategy** (default): Adds/removes a fixed number of workers per scaling event.

```ruby
config.scaling_strategy = :fixed
config.scale_up_increment = 2    # Add 2 workers when scaling up
config.scale_down_decrement = 1  # Remove 1 worker when scaling down
```

**Proportional Strategy**: Scales based on how far over/under thresholds you are.

```ruby
config.scaling_strategy = :proportional
config.scale_up_jobs_per_worker = 50      # Add 1 worker per 50 jobs over threshold
config.scale_up_latency_per_worker = 60   # Add 1 worker per 60s over threshold
```

### Singleton Execution

PostgreSQL advisory locks ensure only one autoscaler instance runs at a time, even across multiple dynos/pods. Each worker configuration gets its own lock key, so different worker types can scale simultaneously.

### Cooldowns

After each scaling event, a cooldown period prevents additional scaling:
- Prevents "flapping" between states
- Gives the platform time to spin up new workers
- Allows queue to stabilize after scaling

Cooldowns are tracked per-worker type, so scaling one worker doesn't block scaling another.

## Environment Variables

### Heroku

| Variable | Description | Required |
|----------|-------------|----------|
| `HEROKU_API_KEY` | Heroku Platform API token | Yes |
| `HEROKU_APP_NAME` | Name of your Heroku app | Yes |

### Kubernetes

| Variable | Description | Required |
|----------|-------------|----------|
| `KUBERNETES_NAMESPACE` | Kubernetes namespace | No (defaults to 'default') |

## Dry Run Mode

Test the autoscaler without making actual changes:

```ruby
SolidQueueHerokuAutoscaler.configure do |config|
  config.dry_run = true
  # ... other config
end
```

In dry-run mode, all decisions are logged but no platform API calls are made.

## Dashboard

The optional dashboard provides a web UI for monitoring the autoscaler:

### Features

- **Overview Dashboard**: Real-time metrics, worker status, and recent events
- **Workers View**: Detailed status for each worker type with configuration and cooldowns
- **Events Log**: Historical record of all scaling decisions with filtering
- **Manual Scaling**: Trigger scale operations directly from the UI

### Setup

1. Generate the dashboard migration:

```bash
rails generate solid_queue_heroku_autoscaler:dashboard
rails db:migrate
```

2. Mount the engine in `config/routes.rb`:

```ruby
authenticate :user, ->(u) { u.admin? } do
  mount SolidQueueHerokuAutoscaler::Dashboard::Engine => "/autoscaler"
end
```

3. Visit `/autoscaler` in your browser

### Event Recording

By default, all scaling events are recorded to the database. Configure in your initializer:

```ruby
SolidQueueHerokuAutoscaler.configure do |config|
  # Record scale_up, scale_down, skipped, and error events (default: true)
  config.record_events = true
  
  # Also record no_change events (verbose, default: false)
  config.record_all_events = false
end
```

### Rake Tasks for Events

```bash
# View recent scale events
bundle exec rake solid_queue_autoscaler:events

# View events for a specific worker
WORKER=critical_worker bundle exec rake solid_queue_autoscaler:events

# Cleanup old events (default: keep 30 days)
bundle exec rake solid_queue_autoscaler:cleanup_events
KEEP_DAYS=7 bundle exec rake solid_queue_autoscaler:cleanup_events
```

## Troubleshooting

### "Could not acquire advisory lock"

Another autoscaler instance is currently running. This is expected behavior — only one instance should run at a time per worker type.

### "Cooldown active"

A recent scaling event triggered the cooldown. Wait for the cooldown to expire or adjust `cooldown_seconds`.

### Workers not scaling

1. Check that `enabled` is `true`
2. Verify platform credentials are set correctly
3. Check metrics with `rake solid_queue_autoscaler:metrics`
4. Enable dry-run to see what decisions would be made
5. Check the logs for error messages

### Kubernetes authentication issues

1. Ensure the service account has permissions to patch deployments
2. Check namespace is correct
3. Verify deployment name matches exactly

## Architecture Notes

This gem acts as a **control plane** for Solid Queue:

- **External to workers**: The autoscaler must not depend on the workers it's scaling
- **Singleton**: Advisory locks ensure only one instance runs globally per worker type
- **Dedicated queue**: Runs on its own queue to avoid competing with business jobs
- **Conservative**: Defaults to gradual scaling with cooldowns
- **Multi-tenant**: Each worker configuration is independent

## License

MIT License. See [LICENSE.txt](LICENSE.txt) for details.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution guidelines.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`bundle exec rspec`)
5. Ensure RuboCop passes (`bundle exec rubocop`)
6. Submit a pull request

## Links

- [GitHub Repository](https://github.com/reillyse/solid_queue_heroku_autoscaler)
- [RubyGems](https://rubygems.org/gems/solid_queue_heroku_autoscaler)
- [Changelog](CHANGELOG.md)

