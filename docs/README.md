# Solid Queue Heroku Autoscaler Documentation

## Quick Links

- [Getting Started](configuration.md) - Setup and configuration
- [API Reference](api_reference.md) - Complete API documentation
- [Architecture](architecture.md) - System design and patterns
- [Adapters](adapters.md) - Plugin architecture for different platforms
- [Error Handling](error_handling.md) - Error types and handling strategies
- [Troubleshooting](troubleshooting.md) - Common issues and solutions

## Overview

Solid Queue Heroku Autoscaler is a control plane for [Solid Queue](https://github.com/rails/solid_queue) on Heroku that automatically scales worker dynos based on queue metrics.

### Key Features

- **Metrics-based scaling**: Scales based on queue depth, job latency, and throughput
- **Singleton execution**: Uses PostgreSQL advisory locks to ensure only one autoscaler runs at a time
- **Safety features**: Cooldowns, min/max limits, dry-run mode
- **Rails integration**: Configuration via initializer, Railtie with rake tasks
- **Flexible execution**: Run as a recurring Solid Queue job or standalone

## Quick Start

### 1. Installation

```ruby
# Gemfile
gem 'solid_queue_heroku_autoscaler'
```

```bash
bundle install
```

### 2. Configuration

```ruby
# config/initializers/solid_queue_autoscaler.rb
SolidQueueHerokuAutoscaler.configure do |config|
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  config.process_type = 'worker'
  
  config.min_workers = 1
  config.max_workers = 10
  
  config.scale_up_queue_depth = 100
  config.scale_up_latency_seconds = 300
  
  config.cooldown_seconds = 120
end
```

### 3. Set Up Recurring Job

```yaml
# config/recurring.yml
autoscaler:
  class: SolidQueueHerokuAutoscaler::AutoscaleJob
  queue: autoscaler
  schedule: every 30 seconds
```

### 4. Run

```ruby
# Manually trigger scaling
result = SolidQueueHerokuAutoscaler.scale!

# Check metrics
metrics = SolidQueueHerokuAutoscaler.metrics
puts "Queue depth: #{metrics.queue_depth}"
```

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Rails Application                    │
├─────────────────────────────────────────────────────────────┤
│  SolidQueueHerokuAutoscaler                                  │
│  ├── Scaler (orchestrator)                                   │
│  │   ├── AdvisoryLock (singleton enforcement)                │
│  │   ├── Metrics (reads from Solid Queue tables)             │
│  │   ├── DecisionEngine (scale up/down/none)                 │
│  │   └── HerokuClient (calls Heroku API)                     │
│  └── AutoscaleJob (for recurring execution)                  │
├─────────────────────────────────────────────────────────────┤
│  Solid Queue Tables (PostgreSQL)                             │
│  ├── solid_queue_ready_executions (pending jobs)             │
│  ├── solid_queue_claimed_executions (in-progress)            │
│  └── solid_queue_processes (worker heartbeats)               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Heroku Platform API                      │
│                     (formation.update)                       │
└─────────────────────────────────────────────────────────────┘
```

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `HEROKU_API_KEY` | Heroku Platform API token | Yes |
| `HEROKU_APP_NAME` | Name of your Heroku app | Yes |

Generate a Heroku API key:

```bash
heroku authorizations:create -d "Solid Queue Autoscaler"
```

## Support

- Check the [Troubleshooting Guide](troubleshooting.md) for common issues
- Review the [API Reference](api_reference.md) for detailed documentation
- See [Architecture](architecture.md) for design decisions
