# Architecture Guide

## Overview

Solid Queue Heroku Autoscaler is a **control plane** for Solid Queue workers on Heroku. It reads queue metrics from PostgreSQL and adjusts worker dyno counts via the Heroku Platform API.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Rails Application                    │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  SolidQueueHerokuAutoscaler                          │    │
│  │                                                      │    │
│  │  ┌──────────────────────────────────────────────┐   │    │
│  │  │  Scaler (Orchestrator)                        │   │    │
│  │  │                                               │   │    │
│  │  │  1. Acquire advisory lock                     │   │    │
│  │  │  2. Collect metrics                           │   │    │
│  │  │  3. Make scaling decision                     │   │    │
│  │  │  4. Execute scaling (if needed)               │   │    │
│  │  │  5. Release lock                              │   │    │
│  │  └──────────────────────────────────────────────┘   │    │
│  │                           │                          │    │
│  │     ┌─────────────────────┼─────────────────────┐   │    │
│  │     │                     │                     │   │    │
│  │     ▼                     ▼                     ▼   │    │
│  │ ┌────────┐         ┌──────────┐          ┌──────┐  │    │
│  │ │Advisory│         │ Metrics  │          │Heroku│  │    │
│  │ │  Lock  │         │Collector │          │Client│  │    │
│  │ └────────┘         └──────────┘          └──────┘  │    │
│  │     │                     │                    │    │    │
│  └─────┼─────────────────────┼────────────────────┼────┘    │
│        │                     │                    │         │
└────────┼─────────────────────┼────────────────────┼─────────┘
         │                     │                    │
         ▼                     ▼                    ▼
┌─────────────┐    ┌─────────────────────┐   ┌──────────┐
│ PostgreSQL  │    │    Solid Queue      │   │  Heroku  │
│ (Advisory   │    │      Tables         │   │ Platform │
│   Locks)    │    │ (ready_executions,  │   │   API    │
│             │    │  claimed_exec, etc) │   │          │
└─────────────┘    └─────────────────────┘   └──────────┘
```

## Component Responsibilities

### Scaler

The main orchestrator that coordinates the scaling process.

**Responsibilities:**
- Acquire advisory lock (ensures singleton execution)
- Coordinate metrics collection, decision making, and scaling
- Handle cooldown periods
- Log all actions and decisions
- Release lock when done

**Key Design Decisions:**
- Non-blocking lock acquisition: Returns skipped result instead of waiting
- Cooldown state is per-process: Stored in class variables
- All operations are atomic: No partial state

### Advisory Lock

PostgreSQL-based distributed lock for singleton execution.

**Why Advisory Locks?**
- **Automatic release**: Released when connection closes (crash-safe)
- **No table pollution**: Doesn't create rows
- **Fast**: No disk I/O for lock operations
- **Cross-dyno**: Works across Heroku dynos

**Implementation:**
```sql
-- Acquire (non-blocking)
SELECT pg_try_advisory_lock(lock_id)

-- Release
SELECT pg_advisory_unlock(lock_id)
```

**Lock ID Generation:**
```ruby
# Convert string key to integer for PostgreSQL
lock_id = Zlib.crc32(lock_key) & 0x7FFFFFFF
```

### Metrics Collector

Collects queue statistics from Solid Queue tables.

**Metrics Collected:**

| Metric | Source | Query |
|--------|--------|-------|
| Queue Depth | `solid_queue_ready_executions` | `COUNT(*)` |
| Oldest Job Age | `solid_queue_ready_executions` | `NOW() - MIN(created_at)` |
| Jobs/Minute | `solid_queue_jobs` | `COUNT(*) WHERE finished_at > NOW() - 1 minute` |
| Claimed Jobs | `solid_queue_claimed_executions` | `COUNT(*)` |
| Failed Jobs | `solid_queue_failed_executions` | `COUNT(*)` |
| Blocked Jobs | `solid_queue_blocked_executions` | `COUNT(*)` |
| Active Workers | `solid_queue_processes` | `COUNT(*) WHERE kind = 'Worker' AND heartbeat recent` |

**Design Decisions:**
- Direct SQL queries: Avoids loading ActiveRecord models
- Queue filtering: Optional filter to specific queues
- Single collection point: All metrics gathered in one call

### Decision Engine

Determines whether to scale up, down, or hold steady.

**Decision Algorithm:**

```
┌─────────────────────────────────────────────────────────────┐
│                    Decision Flow                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Is autoscaler enabled?                                      │
│      NO  → Return no_change                                  │
│      YES ↓                                                   │
│                                                              │
│  Should scale UP?                                            │
│  (queue_depth >= threshold OR latency >= threshold)          │
│  AND current_workers < max_workers                           │
│      YES → Return scale_up                                   │
│      NO  ↓                                                   │
│                                                              │
│  Should scale DOWN?                                          │
│  (queue_depth <= threshold AND latency <= threshold)         │
│  OR queue is idle                                            │
│  AND current_workers > min_workers                           │
│      YES → Return scale_down                                 │
│      NO  ↓                                                   │
│                                                              │
│  Return no_change                                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Key Design Decisions:**
- **Asymmetric thresholds**: Scale up is more aggressive (ANY condition), scale down is conservative (ALL conditions)
- **Favors availability**: When in doubt, keeps workers running
- **Incremental scaling**: Scales by configured increment/decrement, not to target

### Heroku Client

Wrapper around the `platform-api` gem for Heroku API calls.

**API Operations:**
- `formation.info`: Get current dyno count
- `formation.update`: Change dyno count

**Design Decisions:**
- Dry-run mode: Logs without API calls
- Error wrapping: Converts Excon errors to HerokuAPIError
- Stateless: Creates new client per request

## Data Flow

### Scaling Cycle

```
┌─────────────────────────────────────────────────────────────┐
│                    Scaling Cycle                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Job runs (every 30s via Solid Queue recurring)           │
│                                                              │
│  2. Try to acquire advisory lock                             │
│     └─ If locked → skip (another instance running)           │
│                                                              │
│  3. Check if enabled                                         │
│     └─ If disabled → skip                                    │
│                                                              │
│  4. Collect metrics from Solid Queue tables                  │
│     - Queue depth                                            │
│     - Oldest job age (latency)                               │
│     - Jobs per minute (throughput)                           │
│                                                              │
│  5. Get current worker count from Heroku                     │
│                                                              │
│  6. Make scaling decision                                    │
│     - Scale up if load high                                  │
│     - Scale down if load low                                 │
│     - No change if within range                              │
│                                                              │
│  7. Check cooldown                                           │
│     └─ If in cooldown → skip                                 │
│                                                              │
│  8. Execute scaling (if decision != no_change)               │
│     - Call Heroku API                                        │
│     - Record cooldown timestamp                              │
│                                                              │
│  9. Release advisory lock                                    │
│                                                              │
│  10. Return result                                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### State Management

```
┌─────────────────────────────────────────────────────────────┐
│                    State Locations                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  PostgreSQL                                                  │
│  ├── Advisory locks (session-scoped)                         │
│  └── Solid Queue tables (persistent)                         │
│                                                              │
│  Heroku                                                      │
│  └── Formation state (worker count)                          │
│                                                              │
│  Process Memory (class variables)                            │
│  ├── last_scale_up_at                                        │
│  └── last_scale_down_at                                      │
│                                                              │
│  Configuration (application memory)                          │
│  └── All settings (thresholds, limits, etc.)                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Note:** Cooldown state is per-process. This means:
- Across dyno restarts, cooldown resets
- Across multiple dynos, each has its own cooldown
- The advisory lock ensures only one dyno runs at a time

## Design Decisions

### Why External to Workers?

The autoscaler must be **logically external** to the workers it scales:

1. **Chicken-and-egg problem**: If autoscaler runs on workers, when workers are starved, the autoscaler can't run to fix it.

2. **Scale-down paradox**: When deciding to scale down, the autoscaler might be running on the worker that gets terminated.

3. **Multiplicity**: Without coordination, multiple workers might try to scale simultaneously.

**Solution:** Run as a Solid Queue job with:
- Dedicated queue (won't compete with business jobs)
- Single concurrency (only one runs at a time)
- Advisory lock (prevents duplicate executions)

### Why Advisory Locks?

Compared to alternatives:

| Approach | Pros | Cons |
|----------|------|------|
| **Advisory locks** | Fast, automatic release, no schema | Per-connection, not persistent |
| Database row locking | Persistent, visible | Requires table, risk of orphaned locks |
| Redis locks | Fast, distributed | Requires Redis, expiry complexity |
| File locks | Simple | Doesn't work across dynos |

Advisory locks are ideal because:
- Work across Heroku dynos (same database)
- Automatically release on connection close
- No additional infrastructure needed

### Why Cooldowns?

Without cooldowns, rapid oscillation can occur:

```
T=0s:  Queue depth = 100, scale up 2→3
T=30s: Queue depth = 80, no change
T=60s: Queue depth = 40, scale down 3→2
T=90s: Queue depth = 90, scale up 2→3
...
```

This "flapping" wastes resources and can hit Heroku rate limits.

**Cooldown design:**
- Separate cooldowns for scale up and scale down
- Scale up cooldown can be shorter (respond quickly to load)
- Scale down cooldown can be longer (avoid premature termination)

### Why Asymmetric Thresholds?

Scale up triggers on ANY condition exceeding threshold:
```ruby
scale_up if queue_depth >= 100 OR latency >= 300
```

Scale down triggers on ALL conditions below threshold:
```ruby
scale_down if queue_depth <= 10 AND latency <= 30
```

**Rationale:**
- **Availability over cost**: Better to have extra workers than dropped jobs
- **Quick response to load spikes**: Scale up immediately
- **Conservative scale down**: Ensure load is truly low before reducing

### Why Incremental Scaling?

The autoscaler adds/removes workers incrementally (default: 1) rather than jumping to a "target" count.

**Benefits:**
- Gradual response to load changes
- Allows queue to stabilize between scaling events
- Easier to understand and debug
- Less risk of over-provisioning

**If you need faster scaling:**
```ruby
config.scale_up_increment = 3  # Add 3 workers per event
config.scale_up_cooldown_seconds = 30  # Shorter cooldown
```

## Module Structure

```
lib/
├── solid_queue_heroku_autoscaler.rb        # Entry point, module API
└── solid_queue_heroku_autoscaler/
    ├── version.rb                           # VERSION constant
    ├── errors.rb                            # Error classes
    ├── adapters.rb                          # Adapters module loader
    ├── adapters/
    │   ├── base.rb                          # Base adapter interface
    │   └── heroku.rb                        # Heroku adapter
    ├── configuration.rb                     # Configuration class
    ├── advisory_lock.rb                     # PostgreSQL lock wrapper
    ├── metrics.rb                           # Queue metrics collector
    ├── decision_engine.rb                   # Scaling decision logic
    ├── heroku_client.rb                     # Heroku API wrapper (legacy)
    ├── scaler.rb                            # Main orchestrator
    ├── autoscale_job.rb                     # ActiveJob wrapper
    └── railtie.rb                           # Rails integration
```

**Dependency Graph:**

```
SolidQueueHerokuAutoscaler (module)
    └── Scaler
        ├── AdvisoryLock
        │   └── Configuration
        ├── Metrics
        │   └── Configuration
        ├── DecisionEngine
        │   └── Configuration
        └── Adapter (via Configuration)
            └── Adapters::Heroku (default)
                └── Configuration

AutoscaleJob
    └── SolidQueueHerokuAutoscaler (module)
```

## Extension Points

### Custom Adapters (Plugin Architecture)

The adapter system allows you to support different infrastructure platforms:

```ruby
class MyPlatformAdapter < SolidQueueHerokuAutoscaler::Adapters::Base
  def current_workers
    # Return current worker count
  end

  def scale(quantity)
    # Scale to quantity workers
    quantity
  end

  def name
    'MyPlatform'
  end

  def configuration_errors
    # Return array of validation errors
    []
  end
end

# Use the adapter
SolidQueueHerokuAutoscaler.configure do |config|
  config.adapter_class = MyPlatformAdapter
end
```

See the [Adapters Guide](adapters.md) for detailed instructions.

### Custom Metrics

Override the Metrics class to add custom metrics:

```ruby
class CustomMetrics < SolidQueueHerokuAutoscaler::Metrics
  def collect
    result = super
    result.tap do |r|
      r.custom_field = custom_query
    end
  end
end

# Use custom metrics
scaler = SolidQueueHerokuAutoscaler::Scaler.new(
  metrics_collector: CustomMetrics.new
)
```

### Custom Decision Logic

Create a custom decision engine:

```ruby
class CustomDecisionEngine < SolidQueueHerokuAutoscaler::DecisionEngine
  def decide(metrics:, current_workers:)
    # Custom logic here
    Decision.new(
      action: :scale_up,
      from: current_workers,
      to: current_workers + 2,
      reason: "Custom logic"
    )
  end
end
```

### Multiple Process Types

Scale different process types:

```ruby
# Scale web dynos
SolidQueueHerokuAutoscaler.configure do |config|
  config.process_type = 'web'
  # ...
end

# Or create multiple autoscalers
worker_scaler = SolidQueueHerokuAutoscaler::Scaler.new(
  config: worker_config
)

critical_scaler = SolidQueueHerokuAutoscaler::Scaler.new(
  config: critical_worker_config
)
```

## Performance Considerations

### Database Load

Metrics collection runs SQL queries every 30 seconds. The queries are:
- Index-friendly (use existing Solid Queue indexes)
- Read-only (no writes or locks)
- Fast (typically < 10ms)

### Heroku API Rate Limits

Heroku has rate limits (~4500 requests/hour). The autoscaler:
- Makes max 2 API calls per cycle (get formation, update formation)
- With 30s interval: ~240 calls/hour max
- Well under rate limit

### Memory Usage

The autoscaler is lightweight:
- No large data structures
- No caching (fresh metrics each cycle)
- Configuration is single object
- Results are structs (not persisted)

## Security Model

### API Keys

- Stored in environment variables
- Never logged or exposed
- Use dedicated Heroku authorizations (not personal tokens)

### Database Access

- Read-only for metrics
- Uses advisory locks (session-scoped, auto-release)
- No schema modifications

### Attack Surface

- No HTTP endpoints
- No user input processing
- Internal-only (runs within your app)

---

## Kubernetes Alternative Architecture

While this gem is designed for Heroku, the same principles apply to Kubernetes. Here's how a K8s-native autoscaler would look:

### K8s Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                               │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                     Autoscaler Deployment                       │     │
│  │                     (1 replica, singleton)                      │     │
│  │                                                                 │     │
│  │  ┌─────────────────────────────────────────────────────────┐   │     │
│  │  │  solid-queue-autoscaler container                        │   │     │
│  │  │                                                          │   │     │
│  │  │  1. Read metrics from Solid Queue tables                 │   │     │
│  │  │  2. Make scaling decision                                │   │     │
│  │  │  3. Update HPA or Deployment replicas via K8s API        │   │     │
│  │  └─────────────────────────────────────────────────────────┘   │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                    │                                     │
│                                    │ K8s API                             │
│                                    ▼                                     │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │              Worker Deployment (HPA-controlled)                 │     │
│  │                                                                 │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │     │
│  │  │ Worker   │  │ Worker   │  │ Worker   │  │ Worker   │       │     │
│  │  │ Pod 1    │  │ Pod 2    │  │ Pod 3    │  │ Pod N    │       │     │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘       │     │
│  │                                                                 │     │
│  │  replicas: min 1, max 20 (controlled by autoscaler)            │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                    │                                     │
└────────────────────────────────────┼─────────────────────────────────────┘
                                     │
                                     ▼
                          ┌─────────────────────┐
                          │     PostgreSQL      │
                          │  (Solid Queue DB)   │
                          └─────────────────────┘
```

### K8s Implementation Options

#### Option 1: Custom Metrics + HPA (Recommended)

Use Kubernetes HPA with custom metrics from Prometheus:

```yaml
# prometheus-adapter ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: adapter-config
data:
  config.yaml: |
    rules:
    - seriesQuery: 'solid_queue_ready_executions_total'
      resources:
        overrides:
          namespace: {resource: "namespace"}
      name:
        matches: "^(.*)_total$"
        as: "solid_queue_depth"
      metricsQuery: 'sum(solid_queue_ready_executions_total)'
    - seriesQuery: 'solid_queue_oldest_job_age_seconds'
      resources:
        overrides:
          namespace: {resource: "namespace"}
      name:
        matches: "^(.*)$"
        as: "solid_queue_latency"
      metricsQuery: 'max(solid_queue_oldest_job_age_seconds)'

---
# HorizontalPodAutoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: solid-queue-workers-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: solid-queue-workers
  minReplicas: 1
  maxReplicas: 20
  metrics:
  # Scale based on queue depth
  - type: External
    external:
      metric:
        name: solid_queue_depth
      target:
        type: AverageValue
        averageValue: "50"  # Target 50 jobs per worker
  # Also scale based on latency
  - type: External
    external:
      metric:
        name: solid_queue_latency
      target:
        type: Value
        value: "60"  # Scale up if oldest job > 60s
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # 5 min cooldown
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60  # 1 min cooldown
      policies:
      - type: Pods
        value: 2
        periodSeconds: 30
```

#### Option 2: KEDA (Kubernetes Event-Driven Autoscaling)

KEDA provides more sophisticated scaling with PostgreSQL support:

```yaml
# KEDA ScaledObject
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: solid-queue-scaler
spec:
  scaleTargetRef:
    name: solid-queue-workers
  minReplicaCount: 1
  maxReplicaCount: 20
  cooldownPeriod: 120
  pollingInterval: 30
  triggers:
  # Scale based on queue depth
  - type: postgresql
    metadata:
      connectionFromEnv: DATABASE_URL
      query: "SELECT COUNT(*) FROM solid_queue_ready_executions"
      targetQueryValue: "50"  # Target 50 jobs per replica
  # Scale based on oldest job age
  - type: postgresql
    metadata:
      connectionFromEnv: DATABASE_URL
      query: |
        SELECT COALESCE(
          EXTRACT(EPOCH FROM (NOW() - MIN(created_at))),
          0
        ) FROM solid_queue_ready_executions
      targetQueryValue: "60"  # Scale if oldest job > 60s
      activationTargetQueryValue: "30"  # Only activate above 30s
```

#### Option 3: Custom Controller (This Gem Adapted)

Adapt this gem to use Kubernetes API instead of Heroku:

```ruby
# lib/solid_queue_k8s_autoscaler/k8s_client.rb
module SolidQueueK8sAutoscaler
  class K8sClient
    def initialize(config: nil)
      @config = config || SolidQueueK8sAutoscaler.config
      @client = K8s::Client.in_cluster_config
    end

    def current_replicas
      deployment = @client.api('apps/v1')
        .resource('deployments', namespace: @config.namespace)
        .get(@config.deployment_name)
      deployment.spec.replicas
    end

    def scale(replicas)
      return dry_run_scale(replicas) if @config.dry_run?

      @client.api('apps/v1')
        .resource('deployments', namespace: @config.namespace)
        .merge_patch(@config.deployment_name, {
          spec: { replicas: replicas }
        })
      replicas
    end
  end
end
```

### K8s Deployment Manifests

```yaml
# Worker Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: solid-queue-workers
  labels:
    app: solid-queue-workers
spec:
  replicas: 2  # Initial, controlled by HPA/KEDA
  selector:
    matchLabels:
      app: solid-queue-workers
  template:
    metadata:
      labels:
        app: solid-queue-workers
    spec:
      containers:
      - name: worker
        image: myapp:latest
        command: ["bundle", "exec", "rake", "solid_queue:start"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: database-url
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          exec:
            command: ["pgrep", "-f", "solid_queue"]
          initialDelaySeconds: 30
          periodSeconds: 10
      terminationGracePeriodSeconds: 300  # Allow jobs to finish

---
# Autoscaler Deployment (if using custom controller)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: solid-queue-autoscaler
spec:
  replicas: 1  # Singleton
  selector:
    matchLabels:
      app: solid-queue-autoscaler
  template:
    metadata:
      labels:
        app: solid-queue-autoscaler
    spec:
      serviceAccountName: solid-queue-autoscaler
      containers:
      - name: autoscaler
        image: myapp:latest
        command: ["bundle", "exec", "rails", "runner", "AutoscalerLoop.run"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: database-url
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"

---
# RBAC for custom controller
apiVersion: v1
kind: ServiceAccount
metadata:
  name: solid-queue-autoscaler

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: solid-queue-autoscaler
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "patch"]
- apiGroups: ["apps"]
  resources: ["deployments/scale"]
  verbs: ["get", "patch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: solid-queue-autoscaler
subjects:
- kind: ServiceAccount
  name: solid-queue-autoscaler
roleRef:
  kind: Role
  name: solid-queue-autoscaler
  apiGroup: rbac.authorization.k8s.io
```

### Prometheus Metrics Exporter

Expose Solid Queue metrics for Prometheus:

```ruby
# lib/solid_queue_metrics_exporter.rb
class SolidQueueMetricsExporter
  def self.metrics
    {
      solid_queue_ready_executions_total: ready_count,
      solid_queue_claimed_executions_total: claimed_count,
      solid_queue_failed_executions_total: failed_count,
      solid_queue_oldest_job_age_seconds: oldest_job_age,
      solid_queue_jobs_processed_total: jobs_processed_last_minute,
      solid_queue_workers_active: active_workers
    }
  end

  def self.to_prometheus_format
    metrics.map do |name, value|
      "#{name} #{value}"
    end.join("\n")
  end

  private

  def self.ready_count
    SolidQueue::ReadyExecution.count
  end

  def self.claimed_count
    SolidQueue::ClaimedExecution.count
  end

  def self.failed_count
    SolidQueue::FailedExecution.count
  end

  def self.oldest_job_age
    oldest = SolidQueue::ReadyExecution.minimum(:created_at)
    oldest ? (Time.current - oldest).to_f : 0.0
  end

  def self.jobs_processed_last_minute
    SolidQueue::Job.where('finished_at > ?', 1.minute.ago).count
  end

  def self.active_workers
    SolidQueue::Process.where(kind: 'Worker')
      .where('last_heartbeat_at > ?', 5.minutes.ago)
      .count
  end
end

# In routes.rb
get '/metrics', to: ->(env) {
  [
    200,
    { 'Content-Type' => 'text/plain' },
    [SolidQueueMetricsExporter.to_prometheus_format]
  ]
}
```

### Comparison: Heroku vs Kubernetes

| Aspect | Heroku (this gem) | Kubernetes |
|--------|-------------------|------------|
| **Scaling API** | Heroku Platform API | K8s API / HPA / KEDA |
| **Singleton** | PostgreSQL advisory locks | Single replica deployment or leader election |
| **Metrics** | Direct SQL queries | Prometheus + custom metrics |
| **Cooldowns** | In-memory (per-process) | HPA stabilizationWindow |
| **Configuration** | Rails initializer | ConfigMaps, HPA spec |
| **Complexity** | Low (single gem) | Medium-High (multiple components) |
| **Flexibility** | Limited to Heroku | Highly customizable |
| **Cost** | Heroku pricing | Infrastructure dependent |

### When to Use Each Approach

**Use Heroku (this gem) when:**
- Already on Heroku
- Want simple setup
- Don't need complex scaling rules
- Prefer Ruby-native solution

**Use Kubernetes HPA when:**
- Already have Prometheus
- Want native K8s integration
- Need multiple scaling metrics
- Prefer declarative configuration

**Use KEDA when:**
- Need event-driven scaling
- Want scale-to-zero capability
- Have complex scaling triggers
- Need database-native queries
