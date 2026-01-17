# Troubleshooting Guide

## Common Issues

### Autoscaler Not Scaling

**Symptoms:**
- Workers stay at same count despite queue backup
- No scaling logs in output

**Check:**

1. **Is it enabled?**
   ```ruby
   puts SolidQueueAutoscaler.config.enabled?  # Should be true
   ```

2. **Is it in dry-run mode?**
   ```ruby
   puts SolidQueueAutoscaler.config.dry_run?  # Should be false for real scaling
   ```

3. **Are Heroku credentials set?**
   ```ruby
   puts SolidQueueAutoscaler.config.heroku_api_key.present?
   puts SolidQueueAutoscaler.config.heroku_app_name
   ```

4. **Check current metrics:**
   ```ruby
   metrics = SolidQueueAutoscaler.metrics
   puts "Queue depth: #{metrics.queue_depth}"
   puts "Latency: #{metrics.oldest_job_age_seconds}s"
   puts "Threshold: #{SolidQueueAutoscaler.config.scale_up_queue_depth}"
   ```

5. **Try manual scale:**
   ```ruby
   result = SolidQueueAutoscaler.scale!
   puts result.decision.inspect
   puts result.skipped_reason if result.skipped?
   ```

---

### "Could not acquire advisory lock"

**Symptoms:**
```
[Autoscaler] Skipped: Could not acquire advisory lock (another instance is running)
```

**This is normal behavior!** Only one autoscaler should run at a time.

**If you believe no other instance is running:**

1. **Check for stale locks:**
   ```ruby
   # List all advisory locks in PostgreSQL
   ActiveRecord::Base.connection.execute(<<~SQL)
     SELECT * FROM pg_locks WHERE locktype = 'advisory'
   SQL
   ```

2. **Force release (use with caution):**
   ```ruby
   # Only if you're certain no autoscaler is running
   lock_key = SolidQueueAutoscaler.config.lock_key
   lock_id = Zlib.crc32(lock_key) & 0x7FFFFFFF
   ActiveRecord::Base.connection.execute("SELECT pg_advisory_unlock(#{lock_id})")
   ```

3. **Check for crashed processes:**
   Advisory locks are automatically released when the holding connection closes. If a process crashed without closing its connection, the lock may be held by a stale backend.

---

### "Cooldown active"

**Symptoms:**
```
[Autoscaler] Skipped: Cooldown active (45s remaining)
```

**This is expected behavior** after a recent scaling event.

**Solutions:**

1. **Wait it out:** Cooldown prevents flapping

2. **Reduce cooldown (if appropriate):**
   ```ruby
   SolidQueueAutoscaler.configure do |config|
     config.cooldown_seconds = 60  # Default is 120
   end
   ```

3. **Reset cooldowns (testing only):**
   ```ruby
   SolidQueueAutoscaler::Scaler.reset_cooldowns!
   ```

---

### Workers Not Scaling Down

**Symptoms:**
- Queue is empty but workers remain at high count

**Check:**

1. **Are you above min_workers?**
   ```ruby
   current = SolidQueueAutoscaler.current_workers
   min = SolidQueueAutoscaler.config.min_workers
   puts "Current: #{current}, Min: #{min}"
   ```

2. **Check scale-down thresholds:**
   ```ruby
   metrics = SolidQueueAutoscaler.metrics
   config = SolidQueueAutoscaler.config
   
   puts "Queue depth: #{metrics.queue_depth} (threshold: #{config.scale_down_queue_depth})"
   puts "Latency: #{metrics.oldest_job_age_seconds}s (threshold: #{config.scale_down_latency_seconds}s)"
   puts "Claimed jobs: #{metrics.claimed_jobs}"  # Must be 0 for idle
   ```

3. **Check if scale-down cooldown is active:**
   Scale-down has its own cooldown that may be longer than scale-up.

---

### Heroku API Errors

#### 401 Unauthorized

**Symptoms:**
```
HerokuAPIError: Failed to get formation info: Unauthorized
```

**Solutions:**

1. **Check API key is set:**
   ```bash
   echo $HEROKU_API_KEY
   ```

2. **Verify key is valid:**
   ```bash
   heroku authorizations
   ```

3. **Create new authorization:**
   ```bash
   heroku authorizations:create -d "Solid Queue Autoscaler"
   ```

4. **Check for typos in environment variable name**

---

#### 404 Not Found

**Symptoms:**
```
HerokuAPIError: Failed to scale worker to 5: Couldn't find that app
```

**Solutions:**

1. **Check app name:**
   ```bash
   heroku apps
   echo $HEROKU_APP_NAME
   ```

2. **Check for typos in app name**

3. **Verify you have access to the app:**
   ```bash
   heroku apps:info -a $HEROKU_APP_NAME
   ```

---

#### 429 Rate Limited

**Symptoms:**
```
HerokuAPIError: Rate limit exceeded
```

**Solutions:**

1. **This is usually transient** - next run will succeed

2. **Increase cooldown** to reduce API calls:
   ```ruby
   config.cooldown_seconds = 180  # 3 minutes
   ```

3. **Run autoscaler less frequently:**
   ```yaml
   # config/recurring.yml
   autoscaler:
     schedule: every 60 seconds  # Instead of 30
   ```

---

### Missing Solid Queue Tables

**Symptoms:**
```
MetricsError: relation "solid_queue_ready_executions" does not exist
```

**Solutions:**

1. **Run Solid Queue migrations:**
   ```bash
   bin/rails db:migrate:solid_queue
   ```

2. **Check database connection:**
   Ensure you're connecting to the database where Solid Queue tables exist.

3. **If using separate database:**
   ```ruby
   SolidQueueAutoscaler.configure do |config|
     config.database_connection = SolidQueue::Record.connection
   end
   ```

---

### Recurring Job Goes to Wrong Queue (default instead of autoscaler)

**Symptoms:**
```
[ActiveJob] Enqueued SolidQueueAutoscaler::AutoscaleJob to SolidQueue(default)
```

**Cause:** The `queue:` setting in `recurring.yml` **overrides** `config.job_queue`. If you omit `queue:` in your recurring.yml, it defaults to `default`.

**Solution:** Always specify `queue:` in your recurring.yml:

```yaml
# config/recurring.yml
autoscaler:
  class: SolidQueueAutoscaler::AutoscaleJob
  queue: autoscaler  # ⚠️ REQUIRED - must match config.job_queue!
  schedule: every 30 seconds
```

---

### Multiple Workers All Enqueue the Same Recurring Job

**Symptoms:**
```
worker.1: Enqueued SolidQueueAutoscaler::AutoscaleJob
worker.2: Enqueued SolidQueueAutoscaler::AutoscaleJob
worker.3: Enqueued SolidQueueAutoscaler::AutoscaleJob
worker.4: Enqueued SolidQueueAutoscaler::AutoscaleJob
```

**Cause:** Each worker dyno is running its own dispatcher process, and each dispatcher processes `recurring.yml` independently.

**Solutions:**

1. **Run a dedicated dispatcher dyno** (recommended for production):
   ```
   # Procfile
   web: bundle exec puma -C config/puma.rb
   dispatcher: bundle exec rake solid_queue:start SOLID_QUEUE_ONLY_DISPATCH=1
   worker: bundle exec rake solid_queue:start SOLID_QUEUE_ONLY_WORK=1
   ```

2. **Or configure workers to not run dispatcher**:
   ```yaml
   # config/solid_queue.yml
   production:
     dispatchers: []  # No dispatcher on worker dynos
     workers:
       - queues: [autoscaler, default, mailers]
         threads: 5
   ```

3. **Use a separate config for workers vs dispatcher**:
   ```
   # Procfile
   dispatcher: SOLID_QUEUE_CONFIG=config/solid_queue_dispatcher.yml bundle exec rake solid_queue:start
   worker: SOLID_QUEUE_CONFIG=config/solid_queue_worker.yml bundle exec rake solid_queue:start
   ```

---

### Recurring Job Not Running

**Symptoms:**
- Autoscaler job never executes
- No logs from autoscaler

**Check:**

1. **Is recurring.yml configured?**
   ```yaml
   # config/recurring.yml
   autoscaler:
     class: SolidQueueAutoscaler::AutoscaleJob
     queue: autoscaler  # ⚠️ Don't forget this!
     schedule: every 30 seconds
   ```

2. **Is the autoscaler queue defined?**
   ```yaml
   # config/queue.yml
   queues:
     - autoscaler
     - default
   ```

3. **Is a worker processing the autoscaler queue?**
   ```yaml
   workers:
     - queues: [autoscaler]
       threads: 1
   ```

4. **Check Solid Queue logs:**
   ```bash
   tail -f log/solid_queue.log
   ```

5. **Manually enqueue to test:**
   ```ruby
   SolidQueueAutoscaler::AutoscaleJob.perform_later
   ```

---

### Wrong Process Type Being Scaled

**Symptoms:**
- Different dyno type scales instead of workers

**Solutions:**

1. **Check process_type configuration:**
   ```ruby
   puts SolidQueueAutoscaler.config.process_type
   # Should match your Procfile entry
   ```

2. **Check Procfile:**
   ```
   web: bundle exec puma -C config/puma.rb
   worker: bundle exec rake solid_queue:start
   ```

3. **Update configuration:**
   ```ruby
   config.process_type = 'worker'  # or whatever matches Procfile
   ```

---

## Debugging Tips

### Enable Debug Logging

```ruby
SolidQueueAutoscaler.configure do |config|
  config.logger = Logger.new(STDOUT)
  config.logger.level = Logger::DEBUG
end
```

### Check All Metrics

```ruby
metrics = SolidQueueAutoscaler.metrics
puts metrics.to_h.to_yaml
```

### Simulate Scaling Decision

```ruby
config = SolidQueueAutoscaler.config
metrics = SolidQueueAutoscaler.metrics
current = SolidQueueAutoscaler.current_workers

engine = SolidQueueAutoscaler::DecisionEngine.new(config: config)
decision = engine.decide(metrics: metrics, current_workers: current)

puts "Action: #{decision.action}"
puts "From: #{decision.from}"
puts "To: #{decision.to}"
puts "Reason: #{decision.reason}"
```

### Test Heroku Connection

```ruby
client = SolidQueueAutoscaler::HerokuClient.new
puts "Current workers: #{client.current_formation}"
puts "All formations: #{client.formation_list.inspect}"
```

### Check Lock Status

```ruby
lock = SolidQueueAutoscaler::AdvisoryLock.new
if lock.try_lock
  puts "Lock acquired - no other instance running"
  lock.release
else
  puts "Lock held by another instance"
end
```

---

## Diagnostic Script

Create `script/autoscaler_diagnostics.rb`:

```ruby
#!/usr/bin/env ruby
require_relative '../config/environment'

puts "=" * 60
puts "Solid Queue Heroku Autoscaler Diagnostics"
puts "=" * 60

# Configuration
puts "\n📋 Configuration:"
config = SolidQueueAutoscaler.config
puts "  Enabled: #{config.enabled?}"
puts "  Dry Run: #{config.dry_run?}"
puts "  Heroku App: #{config.heroku_app_name}"
puts "  API Key Set: #{config.heroku_api_key.present?}"
puts "  Process Type: #{config.process_type}"
puts "  Min Workers: #{config.min_workers}"
puts "  Max Workers: #{config.max_workers}"
puts "  Scale Up Depth: #{config.scale_up_queue_depth}"
puts "  Scale Up Latency: #{config.scale_up_latency_seconds}s"
puts "  Cooldown: #{config.cooldown_seconds}s"

# Metrics
puts "\n📊 Current Metrics:"
begin
  metrics = SolidQueueAutoscaler.metrics
  puts "  Queue Depth: #{metrics.queue_depth}"
  puts "  Oldest Job Age: #{metrics.oldest_job_age_seconds.round(1)}s"
  puts "  Jobs/Minute: #{metrics.jobs_per_minute}"
  puts "  Claimed Jobs: #{metrics.claimed_jobs}"
  puts "  Failed Jobs: #{metrics.failed_jobs}"
  puts "  Active Workers: #{metrics.active_workers}"
  puts "  Queue Breakdown: #{metrics.queues_breakdown}"
  puts "  Queue Idle: #{metrics.idle?}"
rescue => e
  puts "  ❌ Error: #{e.message}"
end

# Heroku
puts "\n🚀 Heroku Status:"
begin
  workers = SolidQueueAutoscaler.current_workers
  puts "  Current #{config.process_type} dynos: #{workers}"
rescue => e
  puts "  ❌ Error: #{e.message}"
end

# Lock
puts "\n🔒 Advisory Lock:"
lock = SolidQueueAutoscaler::AdvisoryLock.new
if lock.try_lock
  puts "  Lock available (acquired and released)"
  lock.release
else
  puts "  ⚠️  Lock held by another instance"
end

# Decision
puts "\n🤔 Scaling Decision:"
begin
  metrics = SolidQueueAutoscaler.metrics
  workers = SolidQueueAutoscaler.current_workers
  engine = SolidQueueAutoscaler::DecisionEngine.new
  decision = engine.decide(metrics: metrics, current_workers: workers)
  
  puts "  Action: #{decision.action}"
  puts "  From: #{decision.from} -> To: #{decision.to}"
  puts "  Reason: #{decision.reason}"
rescue => e
  puts "  ❌ Error: #{e.message}"
end

# Test Scale
puts "\n🧪 Test Scale (dry run):"
begin
  original_dry_run = config.dry_run
  config.dry_run = true
  
  result = SolidQueueAutoscaler.scale!
  
  if result.success?
    if result.scaled?
      puts "  Would scale: #{result.decision.from} -> #{result.decision.to}"
    elsif result.skipped?
      puts "  Skipped: #{result.skipped_reason}"
    else
      puts "  No change: #{result.decision&.reason}"
    end
  else
    puts "  ❌ Error: #{result.error}"
  end
ensure
  config.dry_run = original_dry_run
end

puts "\n" + "=" * 60
puts "Diagnostics complete"
```

Run with:
```bash
rails runner script/autoscaler_diagnostics.rb
```

---

## Getting Help

1. **Check logs** - Enable debug logging first
2. **Run diagnostics** - Use the diagnostic script above
3. **Check configuration** - Most issues are configuration related
4. **Review metrics** - Ensure thresholds match your workload
5. **Test in dry-run** - Safe way to see what would happen
