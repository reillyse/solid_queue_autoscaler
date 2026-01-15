# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Dashboard UI**: Web-based dashboard for monitoring autoscaler events and status
  - Overview page with real-time metrics, worker status, and recent events
  - Workers page with detailed status, configuration, and cooldown info
  - Events log with filtering by worker type
  - Manual scale trigger from the UI
- **ScaleEvent model**: Tracks all scaling decisions in the database
- **Event recording configuration**: `record_events` and `record_all_events` options
- **New rake tasks**: `events`, `cleanup_events` for managing scale event history
- **Dashboard generator**: `rails generate solid_queue_heroku_autoscaler:dashboard`

## [0.1.0] - 2025-01-XX

### Added

#### Core Features
- **Metrics-based autoscaling** for Solid Queue workers on Heroku and Kubernetes
- **Queue depth monitoring** - Scale based on number of pending jobs
- **Latency monitoring** - Scale based on oldest job age
- **Throughput tracking** - Monitor jobs processed per minute

#### Scaling Strategies
- **Fixed scaling** - Add/remove a fixed number of workers per scaling event
- **Proportional scaling** - Scale workers proportionally based on load level

#### Multi-Worker Support
- **Named configurations** - Configure multiple worker types independently
- **Per-worker cooldowns** - Each worker type has its own cooldown tracking
- **Unique advisory locks** - Parallel scaling of different worker types
- **Queue filtering** - Assign specific queues to each worker configuration

#### Infrastructure Adapters
- **Heroku adapter** - Scale dynos via Heroku Platform API
- **Kubernetes adapter** - Scale deployments via Kubernetes API
- **Pluggable architecture** - Easy to add custom adapters

#### Safety Features
- **PostgreSQL advisory locks** - Singleton execution across multiple dynos
- **Configurable cooldowns** - Prevent rapid scaling oscillations
- **Separate scale-up/down cooldowns** - Fine-tune scaling behavior
- **Min/max worker limits** - Prevent over/under-provisioning
- **Dry-run mode** - Test scaling decisions without making changes

#### Persistence
- **Database-backed cooldown tracking** - Survives dyno restarts
- **Migration generator** - Easy setup of state table
- **Fallback to in-memory** - Works without migration

#### Rails Integration
- **Railtie with rake tasks** - `scale`, `scale_all`, `metrics`, `formation`, `cooldown`, `reset_cooldown`, `workers`
- **Configuration initializer generator** - Quick setup
- **ActiveJob integration** - `AutoscaleJob` for recurring execution
- **Solid Queue recurring job support** - Run autoscaler on schedule

#### Developer Experience
- **Comprehensive test suite** - 356 RSpec examples
- **RuboCop configuration** - Clean, consistent code style
- **GitHub Actions CI** - Automated testing on Ruby 3.1, 3.2, 3.3
- **Detailed logging** - Track all scaling decisions and actions

### Configuration Options

```ruby
SolidQueueHerokuAutoscaler.configure(:worker_name) do |config|
  # Heroku settings
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  config.process_type = 'worker'

  # Kubernetes settings (alternative to Heroku)
  # config.adapter_class = SolidQueueHerokuAutoscaler::Adapters::Kubernetes
  # config.kubernetes_deployment = 'my-worker'
  # config.kubernetes_namespace = 'production'

  # Worker limits
  config.min_workers = 1
  config.max_workers = 10

  # Scaling strategy (:fixed or :proportional)
  config.scaling_strategy = :fixed

  # Scale-up thresholds
  config.scale_up_queue_depth = 100
  config.scale_up_latency_seconds = 300
  config.scale_up_increment = 1

  # Proportional scaling settings
  config.scale_up_jobs_per_worker = 50
  config.scale_up_latency_per_worker = 60

  # Scale-down thresholds
  config.scale_down_queue_depth = 10
  config.scale_down_latency_seconds = 30
  config.scale_down_decrement = 1

  # Cooldowns
  config.cooldown_seconds = 120
  config.scale_up_cooldown_seconds = 60
  config.scale_down_cooldown_seconds = 180

  # Queue filtering
  config.queues = ['default', 'mailers']

  # Behavior
  config.dry_run = false
  config.enabled = true

  # Custom table prefix for Solid Queue tables
  config.table_prefix = 'solid_queue_'
end
```

### Usage Examples

```ruby
# Scale default worker
SolidQueueHerokuAutoscaler.scale!

# Scale specific worker type
SolidQueueHerokuAutoscaler.scale!(:critical_worker)

# Scale all configured workers
SolidQueueHerokuAutoscaler.scale_all!

# Get metrics for a worker
metrics = SolidQueueHerokuAutoscaler.metrics(:default)

# List registered workers
SolidQueueHerokuAutoscaler.registered_workers
```

[0.1.0]: https://github.com/reillyse/solid_queue_heroku_autoscaler/releases/tag/v0.1.0
