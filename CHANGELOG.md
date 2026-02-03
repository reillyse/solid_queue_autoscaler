# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.21] - 2025-02-02

### Added
- **Scale-from-zero documentation** - Updated README and docs/configuration.md with:
  - New "Faster Scale-from-Zero" section explaining the v1.0.20 optimizations
  - Configuration reference for `scale_from_zero_queue_depth` and `scale_from_zero_latency_seconds`
  - Example configuration showing how to customize scale-from-zero behavior
  - Explanation of cooldown bypass and grace period for other workers

## [1.0.20] - 2025-02-02

### Added
- **Scale-from-zero optimization** - New configuration options for faster cold starts when `min_workers = 0`:
  - `scale_from_zero_queue_depth` (default: 1) - Scale up immediately when at 0 workers if queue has at least this many jobs
  - `scale_from_zero_latency_seconds` (default: 1.0) - Job must be at least this old before scaling up (gives other workers a chance to pick it up first)
  - When at 0 workers, uses these lower thresholds instead of the normal `scale_up_queue_depth` and `scale_up_latency_seconds`
  - Cooldowns are bypassed when scaling from 0 workers for fast cold start
  - Comprehensive tests in `scale_to_zero_workflow_spec.rb`

## [1.0.19] - 2025-02-02

### Added
- **AutoscaleJob string/symbol validation** - Detects when `recurring.yml` passes a quoted string like `":all"` instead of the symbol `:all`
  - Raises a helpful `ConfigurationError` with exact before/after YAML examples
  - Plain strings like `"default"` are leniently converted to symbols
  - New `normalize_worker_name` helper method with comprehensive tests

### Improved
- **Better error message for missing Procfile process types** - When `batch_update` returns 404 (process type doesn't exist), the error now explains:
  - The process type doesn't exist in the Procfile
  - How to verify with `heroku ps -a <app_name>`
  - That the configured `process_type` must exactly match a Procfile entry

## [1.0.18] - 2025-01-31

### Fixed
- **Fixed GitHub Actions release workflow** - Added `contents: write` permission to the release job to fix 403 Forbidden error when creating GitHub releases with `GITHUB_TOKEN`

## [1.0.17] - 2025-01-30

### Added
- **Comprehensive scale-to-zero integration tests** - 22 new tests in `spec/integration/scale_to_zero_workflow_spec.rb`:
  - Full lifecycle tests: formation exists → scale to 0 → 404 on info → scale up via `batch_update`
  - Heroku adapter 404 handling verification (returns 0 instead of error)
  - Scaler integration with `min_workers=0` configuration
  - Decision Engine behavior at zero workers
  - Multiple worker types (batch can scale to zero, realtime cannot)
  - Error handling: 404 graceful vs 401/403/500 errors
  - Dry run mode with scale-to-zero
  - Cold start scenario (formation never existed)

## [1.0.16] - 2025-01-30

### Added
- **Comprehensive scale-to-zero documentation** - Added dedicated "Scale to Zero" section in README:
  - Explains how `min_workers = 0` works with Heroku formation behavior
  - Documents the v1.0.15 fix for graceful 404 handling
  - Includes configuration examples and cold-start latency considerations
  - Guidance on where to run the autoscaler (web dyno vs workers)
  - Updated Features list and linked Cost-Optimized example

## [1.0.15] - 2025-01-30

### Fixed
- **Fixed Heroku adapter 404 error when querying scaled-to-zero dynos** - When a dyno type is scaled to 0 and removed from Heroku's formation, the API returns 404. The adapter now handles this gracefully:
  - `current_workers` returns 0 instead of raising an error when formation doesn't exist
  - `scale` falls back to `batch_update` API to create the formation when `update` returns 404
  - Added `create_formation` private method using Heroku's batch_update endpoint
  - This enables full scale-to-zero support with `min_workers = 0`

## [1.0.14] - 2025-01-18

### Added
- **SQLite and MySQL support for advisory locks** - AdvisoryLock now supports multiple database adapters:
  - PostgreSQL: Uses native `pg_try_advisory_lock/pg_advisory_unlock`
  - MySQL/Trilogy: Uses `GET_LOCK/RELEASE_LOCK`
  - SQLite: Uses table-based locking with auto-created locks table
  - Other databases: Falls back to table-based locking
  - Automatic adapter detection via `connection.adapter_name`
  - Stale lock cleanup (locks older than 5 minutes are removed)
  - Lock ownership tracking (`hostname:pid:thread_id`)

- **Comprehensive configuration tests** - Added 100+ tests across Rails and Sinatra dummy apps:
  - Tests for ALL configuration options (job_queue, job_priority, scaling thresholds, cooldowns, etc.)
  - Decision engine threshold tests verifying scaling logic
  - End-to-end tests with mocked Heroku API verifying full scaling workflow
  - Queue name and priority regression tests (prevents jobs going to wrong queue)

- **GitHub Actions integration test workflow** - New CI job that runs dummy app tests:
  - Runs Rails dummy app tests (62 tests)
  - Runs Sinatra dummy app tests (58 tests)
  - Ensures queue name, priority, and E2E scaling tests pass before release

- **Release workflow now requires CI to pass** - Updated release.yml to use `workflow_run` trigger:
  - Release only runs after CI workflow completes successfully
  - All unit tests, integration tests, and linting must pass before publishing

### Fixed
- **Fixed test pollution in autoscale_job_spec** - Changed from using RSpec's `described_class` (which caches class references) to dynamic constant lookup, preventing stale class reference issues when tests reload the AutoscaleJob class

## [1.0.13] - 2025-01-17

### Fixed
- **Fixed AutoscaleJob queue_name type mismatch** - Queue name is now converted to string when set via `apply_job_settings!`
  - ActiveJob internally uses strings for queue names, but the configuration uses symbols
  - This caused jobs to have symbol queue names (`:autoscaler`) instead of string (`"autoscaler"`)
  - Now `apply_job_settings!` calls `.to_s` on the job_queue to ensure consistent string format

## [1.0.12] - 2025-01-17

### Fixed
- **Fixed AutoscaleJob being enqueued to "default" queue** - Added `queue_as :autoscaler` to the job class
  - The issue was that SolidQueue recurring jobs capture the queue name during initialization, BEFORE Rails `after_initialize` hooks run
  - Without a static `queue_as` in the class, jobs defaulted to the "default" queue
  - The `apply_job_settings!` method can still override this via configuration, but the default must be set in the class for SolidQueue recurring to work correctly

## [1.0.11] - 2025-01-17

### Fixed

#### Critical Fixes
- **Thread safety** - Fixed race condition in mutex initialization (`scaler.rb`). Changed from lazy `@cooldown_mutex ||= Mutex.new` to thread-safe class constant `COOLDOWN_MUTEX`
- **SQL injection prevention** - Added regex validation for `table_prefix` configuration to only allow `[a-z0-9_]+` pattern
- **PgBouncer documentation** - Added prominent warning in `advisory_lock.rb` about incompatibility with PgBouncer transaction pooling mode

#### High Priority Fixes
- **CooldownTracker caching** - Added 5-minute TTL for `table_exists?` cache and `reset_table_exists_cache!` method for manual invalidation
- **ScaleEvent naming** - Renamed `create!` to `create` (non-bang) since it catches exceptions and returns nil. Added `create!` as deprecated alias for backward compatibility
- **Decision struct mutation** - Fixed mutation of Decision struct when clamping target workers. Now creates a new Decision instead of modifying the existing one
- **ZeroDivisionError prevention** - Added validation that `scale_up_jobs_per_worker`, `scale_up_latency_per_worker`, and `scale_down_jobs_per_worker` must be > 0 when using proportional scaling

#### Medium Priority Fixes
- **Retry logic for adapters** - Added exponential backoff retry (3 attempts with 1s/2s/4s delays) for transient network errors in both Heroku and Kubernetes adapters
- **Time parsing** - Fixed timezone handling in `cooldown_tracker.rb` to properly handle Time, DateTime, and String values
- **Dashboard query optimization** - Batched cooldown state retrieval in `worker_status` to reduce database queries
- **Metrics nil handling** - `oldest_job_age_seconds` now returns `0.0` instead of `nil` when no jobs exist
- **Kubernetes timeout** - Added 30-second timeout configuration to kubeclient API calls

#### Low Priority Fixes
- **Safe logger calls** - Added safe navigation (`logger&.warn`) throughout to prevent nil errors
- **SQL table quoting** - Now uses `connection.quote_table_name()` for all table name interpolations
- **Rails.logger nil check** - Added proper nil check before using `Rails.logger` in `scale_event.rb`

## [1.0.10] - 2025-01-17

### Fixed
- **Fixed Dashboard not finding events table in multi-database setups** - `ScaleEvent.default_connection` now correctly uses `SolidQueue::Record.connection` instead of `ActiveRecord::Base.connection`
  - This was causing "Events table not found" errors when using a separate queue database

## [1.0.9] - 2025-01-17

### Added
- **`verify_setup!` method** - New diagnostic method to verify installation is correct
  - Checks database connection (multi-database aware)
  - Verifies both autoscaler tables exist with correct columns
  - Tests adapter connectivity
  - Returns a `VerificationResult` struct with `ok?`, `tables_exist?`, `cooldowns_shared?` methods
  - Run `SolidQueueAutoscaler.verify_setup!` in Rails console to diagnose issues
- **`verify_install!` alias** - Alias for `verify_setup!`
- **`persist_cooldowns` configuration option** - Control whether cooldowns are stored in database (default: true) or in-memory

### Fixed
- **Fixed multi-database migration bug** - Migration generator now correctly handles `migrations_paths` as a string (not just array)
  - Previously, migrations would be placed in a `d/` directory instead of `db/queue_migrate/` due to calling `.first` on a string
  - Migrations now auto-detect the correct directory from your `database.yml` configuration
- **Removed unreliable `self.connection` override** from migration templates - This didn't work because `SolidQueue::Record` isn't loaded at migration time
- **Improved migration generator output** - Clearer instructions for single-database vs multi-database setups

### Changed
- `verify_setup!` returns `nil` instead of the result object to keep console output clean
- Migration templates no longer try to override the database connection (rely on Rails native multi-database support instead)

## [1.0.8] - 2025-01-17

### Added
- **`job_queue` configuration option** - Configure which queue the AutoscaleJob runs on (default: `:autoscaler`)
- **`job_priority` configuration option** - Set job priority for AutoscaleJob (lower = higher priority)
- **Multi-database migration support** - Migration templates now automatically create tables in the same database as Solid Queue
- **Common Configuration Examples** - New README section with 8 copy-paste ready configurations for different use cases:
  - Simple/Starter setup
  - Cost-Optimized (scale to zero)
  - E-Commerce/SaaS (multiple worker types)
  - High-Volume API (webhook processing with proportional scaling)
  - Data Processing/ETL
  - High-Availability
  - Kubernetes
  - Development/Testing
- **Expanded Troubleshooting** - 15+ new troubleshooting topics with code examples
- **Configuration Comparison Table** - Quick reference for common configurations

### Changed
- AutoscaleJob now uses `queue_as` and `queue_with_priority` blocks for dynamic queue/priority selection
- Each worker configuration can have its own `job_queue` and `job_priority` settings

## [1.0.7] - 2025-01-16

### Fixed
- **Fixed Dashboard MissingExactTemplate error** - Views now work correctly in Rails applications
- Moved views from `lib/` to `app/views/` (standard Rails engine structure)
- Added `prepend_view_path Engine.root.join('app', 'views')` to ApplicationController for reliable view path resolution
- Updated gemspec to include `app/**/*` in files array
- Fixed layout path reference to `solid_queue_autoscaler/dashboard`

## [1.0.6] - 2025-01-16

### Fixed
- Fixed Dashboard templates not being found (`MissingExactTemplate` error)
- View paths are now captured at class definition time instead of inside callbacks where `__dir__` was evaluated incorrectly
- Properly configures both engine and application view paths for reliable template resolution

## [1.0.5] - 2025-01-16

### Added
- Auto-detect `SolidQueue::Record.connection` for multi-database setups
- No longer need to manually configure `database_connection` when using Solid Queue's separate database
- Connection priority: 1) explicit `database_connection`, 2) `SolidQueue::Record.connection`, 3) `ActiveRecord::Base.connection`

## [1.0.4] - 2025-01-16

### Fixed
- Fixed YAML syntax in README examples that caused parsing errors when users copied them
- Changed `args: [:all]` to block array syntax `args:\n    - :all` to avoid YAML flow node parsing issues with symbols

## [1.0.3] - 2025-01-16

### Fixed
- Fixed remaining old gem name references in generator templates and codebuff.json
- Renamed spec file from `solid_queue_heroku_autoscaler_spec.rb` to `solid_queue_autoscaler_spec.rb`

## [1.0.2] - 2025-01-16

### Fixed
- Fixed Dashboard::Engine not loading properly in Rails applications due to load order issues
- Engine is now loaded via a railtie initializer to ensure Rails is fully initialized first
- Verified working in real Rails applications

## [1.0.1] - 2025-01-16 [YANKED]

### Fixed
- Attempted fix for Dashboard::Engine loading (incomplete)

## [1.0.0] - 2025-01-16

### Changed

- **Renamed gem** from `solid_queue_heroku_autoscaler` to `solid_queue_autoscaler` to better reflect multi-platform support (Heroku, Kubernetes, custom adapters)
- **Renamed module** from `SolidQueueHerokuAutoscaler` to `SolidQueueAutoscaler`
- Version reset to 1.0.0 for the new gem name

### Migration from solid_queue_heroku_autoscaler

1. Update your Gemfile:
   ```ruby
   # Old
   gem "solid_queue_heroku_autoscaler"
   # New
   gem "solid_queue_autoscaler"
   ```

2. Update your initializer:
   ```ruby
   # Old
   SolidQueueHerokuAutoscaler.configure do |config|
   # New
   SolidQueueAutoscaler.configure do |config|
   ```

3. Update any rake task references:
   ```bash
   # Old
   rake solid_queue_heroku_autoscaler:scale
   # New  
   rake solid_queue_autoscaler:scale
   ```

## [0.2.1] - 2025-01-16

### Fixed

- **Adapter symbol support**: Fixed `config.adapter = :heroku` and `config.adapter = :kubernetes` not working correctly. The adapter setter now properly converts symbols to adapter instances.
- Also supports `config.adapter = :k8s` as an alias for `:kubernetes`

## [0.2.0] - 2025-01-20

### Added

- **Dashboard UI**: Web-based dashboard for monitoring autoscaler events and status
  - Overview page with real-time metrics, worker status, and recent events
  - Workers page with detailed status, configuration, and cooldown info
  - Events log with filtering by worker type
  - Manual scale trigger from the UI
- **ScaleEvent model**: Tracks all scaling decisions in the database
- **Event recording configuration**: `record_events` and `record_all_events` options
- **New rake tasks**: `events`, `cleanup_events` for managing scale event history
- **Dashboard generator**: `rails generate solid_queue_autoscaler:dashboard`
- **Ruby 3.4 support**: Added CI testing for Ruby 3.4

## [0.1.0] - 2025-01-19

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
SolidQueueAutoscaler.configure(:worker_name) do |config|
  # Heroku settings
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  config.process_type = 'worker'

  # Kubernetes settings (alternative to Heroku)
  # config.adapter_class = SolidQueueAutoscaler::Adapters::Kubernetes
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
SolidQueueAutoscaler.scale!

# Scale specific worker type
SolidQueueAutoscaler.scale!(:critical_worker)

# Scale all configured workers
SolidQueueAutoscaler.scale_all!

# Get metrics for a worker
metrics = SolidQueueAutoscaler.metrics(:default)

# List registered workers
SolidQueueAutoscaler.registered_workers
```

[1.0.0]: https://github.com/reillyse/solid_queue_autoscaler/releases/tag/v1.0.0
[0.2.1]: https://github.com/reillyse/solid_queue_heroku_autoscaler/releases/tag/v0.2.1
[0.2.0]: https://github.com/reillyse/solid_queue_heroku_autoscaler/releases/tag/v0.2.0
[0.1.0]: https://github.com/reillyse/solid_queue_heroku_autoscaler/releases/tag/v0.1.0
