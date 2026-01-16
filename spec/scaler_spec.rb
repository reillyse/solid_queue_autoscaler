# frozen_string_literal: true

RSpec.describe SolidQueueAutoscaler::Scaler do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil) }

  let(:adapter) do
    instance_double(
      SolidQueueAutoscaler::Adapters::Heroku,
      current_workers: 2,
      scale: 3,
      name: 'Heroku'
    )
  end

  let(:config) do
    SolidQueueAutoscaler::Configuration.new.tap do |c|
      c.heroku_api_key = 'test-api-key'
      c.heroku_app_name = 'test-app'
      c.process_type = 'worker'
      c.min_workers = 1
      c.max_workers = 10
      c.scale_up_queue_depth = 100
      c.scale_up_latency_seconds = 300
      c.scale_up_increment = 1
      c.scale_down_queue_depth = 10
      c.scale_down_latency_seconds = 30
      c.scale_down_decrement = 1
      c.cooldown_seconds = 120
      c.dry_run = false
      c.enabled = true
      c.logger = logger
      c.adapter = adapter
    end
  end

  let(:lock) { instance_double(SolidQueueAutoscaler::AdvisoryLock) }

  let(:metrics_result) do
    SolidQueueAutoscaler::Metrics::Result.new(
      queue_depth: 50,
      oldest_job_age_seconds: 60.0,
      jobs_per_minute: 100,
      claimed_jobs: 5,
      failed_jobs: 0,
      blocked_jobs: 0,
      active_workers: 2,
      queues_breakdown: { 'default' => 30, 'mailers' => 20 },
      collected_at: Time.current
    )
  end

  let(:metrics_collector) { instance_double(SolidQueueAutoscaler::Metrics, collect: metrics_result) }
  let(:decision_engine) { instance_double(SolidQueueAutoscaler::DecisionEngine) }

  subject(:scaler) { described_class.new(config: config) }

  before do
    allow(SolidQueueAutoscaler::AdvisoryLock).to receive(:new).and_return(lock)
    allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)
    allow(SolidQueueAutoscaler::DecisionEngine).to receive(:new).and_return(decision_engine)
    allow(lock).to receive(:try_lock).and_return(true)
    allow(lock).to receive(:release)
    allow(lock).to receive(:with_lock).and_yield
  end

  describe 'ScaleResult struct' do
    let(:decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_up,
        from: 2,
        to: 3,
        reason: 'test reason'
      )
    end

    describe '#success?' do
      it 'returns true when success is true' do
        result = described_class::ScaleResult.new(success: true)
        expect(result.success?).to be(true)
      end

      it 'returns false when success is false' do
        result = described_class::ScaleResult.new(success: false)
        expect(result.success?).to be(false)
      end

      it 'returns false when success is nil' do
        result = described_class::ScaleResult.new(success: nil)
        expect(result.success?).to be(false)
      end
    end

    describe '#skipped?' do
      it 'returns true when skipped_reason is present' do
        result = described_class::ScaleResult.new(skipped_reason: 'some reason')
        expect(result.skipped?).to be(true)
      end

      it 'returns false when skipped_reason is nil' do
        result = described_class::ScaleResult.new(skipped_reason: nil)
        expect(result.skipped?).to be(false)
      end
    end

    describe '#scaled?' do
      it 'returns true when success and decision is scale_up' do
        result = described_class::ScaleResult.new(success: true, decision: decision)
        expect(result.scaled?).to be(true)
      end

      it 'returns false when success but decision is no_change' do
        no_change_decision = SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :no_change,
          from: 2,
          to: 2,
          reason: 'metrics ok'
        )
        result = described_class::ScaleResult.new(success: true, decision: no_change_decision)
        expect(result.scaled?).to be(false)
      end

      it 'returns false when not success' do
        result = described_class::ScaleResult.new(success: false, decision: decision)
        expect(result.scaled?).to be(false)
      end

      it 'returns false when decision is nil' do
        result = described_class::ScaleResult.new(success: true, decision: nil)
        expect(result.scaled?).to be_falsey
      end
    end
  end

  describe '.reset_cooldowns!' do
    it 'resets last_scale_up_at to nil' do
      described_class.last_scale_up_at = Time.current
      described_class.reset_cooldowns!
      expect(described_class.last_scale_up_at).to be_nil
    end

    it 'resets last_scale_down_at to nil' do
      described_class.last_scale_down_at = Time.current
      described_class.reset_cooldowns!
      expect(described_class.last_scale_down_at).to be_nil
    end
  end

  describe '#run' do
    context 'when autoscaler is disabled' do
      before { config.enabled = false }

      it 'returns a skipped result' do
        result = scaler.run
        expect(result.skipped?).to be(true)
        expect(result.skipped_reason).to eq('Autoscaler is disabled')
      end

      it 'does not try to acquire the lock' do
        scaler.run
        expect(lock).not_to have_received(:try_lock)
      end

      it 'does not collect metrics' do
        scaler.run
        expect(metrics_collector).not_to have_received(:collect)
      end
    end

    context 'when lock cannot be acquired' do
      before { allow(lock).to receive(:try_lock).and_return(false) }

      it 'returns a skipped result' do
        result = scaler.run
        expect(result.skipped?).to be(true)
        expect(result.skipped_reason).to include('Could not acquire advisory lock')
      end

      it 'does not collect metrics' do
        scaler.run
        expect(metrics_collector).not_to have_received(:collect)
      end

      it 'does not try to scale' do
        scaler.run
        expect(adapter).not_to have_received(:scale)
      end
    end

    context 'when lock is acquired successfully' do
      it 'releases the lock after execution' do
        allow(decision_engine).to receive(:decide).and_return(
          SolidQueueAutoscaler::DecisionEngine::Decision.new(
            action: :no_change,
            from: 2,
            to: 2,
            reason: 'metrics ok'
          )
        )

        scaler.run

        expect(lock).to have_received(:release)
      end

      it 'releases the lock even when an error occurs' do
        allow(metrics_collector).to receive(:collect).and_raise(StandardError.new('DB error'))

        scaler.run

        expect(lock).to have_received(:release)
      end
    end

    context 'full scaling workflow - scale up' do
      let(:scale_up_metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 150,
          oldest_job_age_seconds: 400.0,
          jobs_per_minute: 50,
          claimed_jobs: 10,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 2,
          queues_breakdown: { 'default' => 150 },
          collected_at: Time.current
        )
      end

      let(:scale_up_decision) do
        SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :scale_up,
          from: 2,
          to: 3,
          reason: 'queue_depth=150 >= 100'
        )
      end

      before do
        allow(metrics_collector).to receive(:collect).and_return(scale_up_metrics)
        allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
        allow(adapter).to receive(:current_workers).and_return(2)
        allow(adapter).to receive(:scale).and_return(3)
      end

      it 'collects metrics' do
        scaler.run
        expect(metrics_collector).to have_received(:collect)
      end

      it 'gets current worker count from adapter' do
        scaler.run
        expect(adapter).to have_received(:current_workers)
      end

      it 'asks decision engine for scaling decision' do
        scaler.run
        expect(decision_engine).to have_received(:decide).with(
          metrics: scale_up_metrics,
          current_workers: 2
        )
      end

      it 'calls adapter.scale with the target workers' do
        scaler.run
        expect(adapter).to have_received(:scale).with(3)
      end

      it 'returns a successful result' do
        result = scaler.run
        expect(result.success?).to be(true)
      end

      it 'returns scaled? as true' do
        result = scaler.run
        expect(result.scaled?).to be(true)
      end

      it 'includes the decision in the result' do
        result = scaler.run
        expect(result.decision).to eq(scale_up_decision)
      end

      it 'includes the metrics in the result' do
        result = scaler.run
        expect(result.metrics).to eq(scale_up_metrics)
      end

      it 'includes executed_at timestamp' do
        result = scaler.run
        expect(result.executed_at).to be_within(1.second).of(Time.current)
      end

      it 'records the scale-up time' do
        described_class.reset_cooldowns!
        scaler.run
        expect(described_class.last_scale_up_at).to be_within(1.second).of(Time.current)
      end

      it 'logs the decision' do
        scaler.run
        expect(logger).to have_received(:info).with(/Evaluated.*scale_up/)
      end

      it 'logs the scale action' do
        scaler.run
        expect(logger).to have_received(:info).with(/Scaling scale_up.*2 -> 3/)
      end
    end

    context 'full scaling workflow - scale down' do
      let(:scale_down_metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 5,
          oldest_job_age_seconds: 10.0,
          jobs_per_minute: 200,
          claimed_jobs: 1,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 5,
          queues_breakdown: { 'default' => 5 },
          collected_at: Time.current
        )
      end

      let(:scale_down_decision) do
        SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :scale_down,
          from: 5,
          to: 4,
          reason: 'queue_depth=5 <= 10'
        )
      end

      before do
        allow(metrics_collector).to receive(:collect).and_return(scale_down_metrics)
        allow(decision_engine).to receive(:decide).and_return(scale_down_decision)
        allow(adapter).to receive(:current_workers).and_return(5)
        allow(adapter).to receive(:scale).and_return(4)
      end

      it 'calls adapter.scale with the target workers' do
        scaler.run
        expect(adapter).to have_received(:scale).with(4)
      end

      it 'returns scaled? as true' do
        result = scaler.run
        expect(result.scaled?).to be(true)
      end

      it 'records the scale-down time' do
        described_class.reset_cooldowns!
        scaler.run
        expect(described_class.last_scale_down_at).to be_within(1.second).of(Time.current)
      end

      it 'logs the scale-down action' do
        scaler.run
        expect(logger).to have_received(:info).with(/Scaling scale_down.*5 -> 4/)
      end
    end

    context 'full scaling workflow - no change' do
      let(:normal_metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 50,
          oldest_job_age_seconds: 60.0,
          jobs_per_minute: 100,
          claimed_jobs: 5,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 3,
          queues_breakdown: { 'default' => 50 },
          collected_at: Time.current
        )
      end

      let(:no_change_decision) do
        SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :no_change,
          from: 3,
          to: 3,
          reason: 'metrics within normal range'
        )
      end

      before do
        allow(metrics_collector).to receive(:collect).and_return(normal_metrics)
        allow(decision_engine).to receive(:decide).and_return(no_change_decision)
        allow(adapter).to receive(:current_workers).and_return(3)
      end

      it 'does not call adapter.scale' do
        scaler.run
        expect(adapter).not_to have_received(:scale)
      end

      it 'returns a successful result' do
        result = scaler.run
        expect(result.success?).to be(true)
      end

      it 'returns scaled? as false' do
        result = scaler.run
        expect(result.scaled?).to be(false)
      end

      it 'does not update cooldown timestamps' do
        described_class.reset_cooldowns!
        scaler.run
        expect(described_class.last_scale_up_at).to be_nil
        expect(described_class.last_scale_down_at).to be_nil
      end
    end

    context 'cooldown behavior - scale up cooldown active' do
      let(:scale_up_decision) do
        SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :scale_up,
          from: 2,
          to: 3,
          reason: 'queue_depth high'
        )
      end

      before do
        config.cooldown_seconds = 120
        described_class.last_scale_up_at = Time.current - 60 # 60 seconds ago
        allow(metrics_collector).to receive(:collect).and_return(metrics_result)
        allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
        allow(adapter).to receive(:current_workers).and_return(2)
      end

      it 'returns a skipped result' do
        result = scaler.run
        expect(result.skipped?).to be(true)
      end

      it 'includes cooldown remaining time in reason' do
        result = scaler.run
        expect(result.skipped_reason).to match(/Cooldown active.*\d+.*remaining/)
      end

      it 'does not call adapter.scale' do
        scaler.run
        expect(adapter).not_to have_received(:scale)
      end

      it 'does not update scale-up timestamp' do
        original_time = described_class.last_scale_up_at
        scaler.run
        expect(described_class.last_scale_up_at).to eq(original_time)
      end

      it 'still includes decision and metrics in result' do
        result = scaler.run
        expect(result.decision).to eq(scale_up_decision)
        expect(result.metrics).to eq(metrics_result)
      end
    end

    context 'cooldown behavior - scale down cooldown active' do
      let(:scale_down_decision) do
        SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :scale_down,
          from: 5,
          to: 4,
          reason: 'queue_depth low'
        )
      end

      before do
        config.cooldown_seconds = 120
        described_class.last_scale_down_at = Time.current - 30 # 30 seconds ago
        allow(metrics_collector).to receive(:collect).and_return(metrics_result)
        allow(decision_engine).to receive(:decide).and_return(scale_down_decision)
        allow(adapter).to receive(:current_workers).and_return(5)
      end

      it 'returns a skipped result' do
        result = scaler.run
        expect(result.skipped?).to be(true)
      end

      it 'does not call adapter.scale' do
        scaler.run
        expect(adapter).not_to have_received(:scale)
      end
    end

    context 'cooldown behavior - cooldown expired' do
      let(:scale_up_decision) do
        SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :scale_up,
          from: 2,
          to: 3,
          reason: 'queue_depth high'
        )
      end

      before do
        config.cooldown_seconds = 120
        described_class.last_scale_up_at = Time.current - 180 # 180 seconds ago (expired)
        allow(metrics_collector).to receive(:collect).and_return(metrics_result)
        allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
        allow(adapter).to receive(:current_workers).and_return(2)
        allow(adapter).to receive(:scale).and_return(3)
      end

      it 'proceeds with scaling' do
        scaler.run
        expect(adapter).to have_received(:scale).with(3)
      end

      it 'returns scaled? as true' do
        result = scaler.run
        expect(result.scaled?).to be(true)
      end

      it 'updates the cooldown timestamp' do
        scaler.run
        expect(described_class.last_scale_up_at).to be_within(1.second).of(Time.current)
      end
    end

    context 'cooldown behavior - separate cooldowns for scale up and scale down' do
      let(:scale_up_decision) do
        SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :scale_up,
          from: 2,
          to: 3,
          reason: 'queue_depth high'
        )
      end

      before do
        config.scale_up_cooldown_seconds = 60
        config.scale_down_cooldown_seconds = 300
        # Scale down was recent, but scale up cooldown is shorter and expired
        described_class.last_scale_down_at = Time.current - 30
        described_class.last_scale_up_at = nil
        allow(metrics_collector).to receive(:collect).and_return(metrics_result)
        allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
        allow(adapter).to receive(:current_workers).and_return(2)
        allow(adapter).to receive(:scale).and_return(3)
      end

      it 'allows scale up even if scale down cooldown is active' do
        scaler.run
        expect(adapter).to have_received(:scale).with(3)
      end
    end

    context 'error handling - metrics collection error' do
      before do
        allow(metrics_collector).to receive(:collect)
          .and_raise(StandardError.new('Database connection failed'))
      end

      it 'returns an error result' do
        result = scaler.run
        expect(result.success?).to be(false)
      end

      it 'includes the error in the result' do
        result = scaler.run
        expect(result.error).to be_a(StandardError)
        expect(result.error.message).to eq('Database connection failed')
      end

      it 'logs the error' do
        scaler.run
        expect(logger).to have_received(:error).with(/Error.*Database connection failed/)
      end

      it 'does not attempt to scale' do
        scaler.run
        expect(adapter).not_to have_received(:scale)
      end
    end

    context 'error handling - adapter current_workers error' do
      before do
        allow(metrics_collector).to receive(:collect).and_return(metrics_result)
        allow(adapter).to receive(:current_workers)
          .and_raise(SolidQueueAutoscaler::HerokuAPIError.new('API timeout'))
      end

      it 'returns an error result' do
        result = scaler.run
        expect(result.success?).to be(false)
      end

      it 'includes the HerokuAPIError in the result' do
        result = scaler.run
        expect(result.error).to be_a(SolidQueueAutoscaler::HerokuAPIError)
      end
    end

    context 'error handling - adapter scale error' do
      let(:scale_up_decision) do
        SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :scale_up,
          from: 2,
          to: 3,
          reason: 'queue_depth high'
        )
      end

      before do
        allow(metrics_collector).to receive(:collect).and_return(metrics_result)
        allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
        allow(adapter).to receive(:current_workers).and_return(2)
        allow(adapter).to receive(:scale)
          .and_raise(SolidQueueAutoscaler::HerokuAPIError.new('Rate limited', status_code: 429))
      end

      it 'returns an error result' do
        result = scaler.run
        expect(result.success?).to be(false)
      end

      it 'includes the error in the result' do
        result = scaler.run
        expect(result.error).to be_a(SolidQueueAutoscaler::HerokuAPIError)
        expect(result.error.status_code).to eq(429)
      end

      it 'does not update cooldown timestamp on failure' do
        described_class.reset_cooldowns!
        scaler.run
        expect(described_class.last_scale_up_at).to be_nil
      end
    end

    context 'error handling - decision engine error' do
      before do
        allow(metrics_collector).to receive(:collect).and_return(metrics_result)
        allow(adapter).to receive(:current_workers).and_return(2)
        allow(decision_engine).to receive(:decide)
          .and_raise(StandardError.new('Decision engine bug'))
      end

      it 'returns an error result' do
        result = scaler.run
        expect(result.success?).to be(false)
        expect(result.error.message).to eq('Decision engine bug')
      end
    end
  end

  describe '#run!' do
    context 'when lock is acquired' do
      let(:no_change_decision) do
        SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :no_change,
          from: 2,
          to: 2,
          reason: 'metrics ok'
        )
      end

      before do
        allow(decision_engine).to receive(:decide).and_return(no_change_decision)
        allow(adapter).to receive(:current_workers).and_return(2)
      end

      it 'uses blocking lock via with_lock' do
        scaler.run!
        expect(lock).to have_received(:with_lock)
      end

      it 'executes scaling logic' do
        result = scaler.run!
        expect(result.success?).to be(true)
      end

      it 'collects metrics' do
        scaler.run!
        expect(metrics_collector).to have_received(:collect)
      end
    end

    context 'when lock acquisition fails' do
      before do
        allow(lock).to receive(:with_lock)
          .and_raise(SolidQueueAutoscaler::LockError.new('Lock timeout'))
      end

      it 'raises the lock error' do
        expect { scaler.run! }.to raise_error(SolidQueueAutoscaler::LockError, /Lock timeout/)
      end
    end

    context 'when scaling succeeds' do
      let(:scale_up_decision) do
        SolidQueueAutoscaler::DecisionEngine::Decision.new(
          action: :scale_up,
          from: 2,
          to: 3,
          reason: 'queue_depth high'
        )
      end

      before do
        allow(metrics_collector).to receive(:collect).and_return(metrics_result)
        allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
        allow(adapter).to receive(:current_workers).and_return(2)
        allow(adapter).to receive(:scale).and_return(3)
      end

      it 'scales successfully' do
        result = scaler.run!
        expect(result.scaled?).to be(true)
      end
    end
  end

  describe 'logging' do
    let(:scale_up_decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_up,
        from: 2,
        to: 3,
        reason: 'queue_depth=150 >= 100'
      )
    end

    let(:high_metrics) do
      SolidQueueAutoscaler::Metrics::Result.new(
        queue_depth: 150,
        oldest_job_age_seconds: 120.0,
        jobs_per_minute: 50,
        claimed_jobs: 5,
        failed_jobs: 0,
        blocked_jobs: 0,
        active_workers: 2,
        queues_breakdown: { 'default' => 150 },
        collected_at: Time.current
      )
    end

    before do
      allow(metrics_collector).to receive(:collect).and_return(high_metrics)
      allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
      allow(adapter).to receive(:current_workers).and_return(2)
      allow(adapter).to receive(:scale).and_return(3)
    end

    it 'logs evaluation with metrics details' do
      scaler.run
      expect(logger).to have_received(:info).with(
        /Evaluated.*action=scale_up.*workers=2->3.*queue_depth=150.*latency=120s.*reason=/
      )
    end

    it 'logs scaling action' do
      scaler.run
      expect(logger).to have_received(:info).with(
        /Scaling scale_up.*2 -> 3 workers/
      )
    end

    context 'when in dry-run mode' do
      before { config.dry_run = true }

      it 'prefixes scale action log with [DRY RUN]' do
        scaler.run
        expect(logger).to have_received(:info).with(/\[DRY RUN\].*Scaling/)
      end
    end

    context 'when skipped' do
      before { config.enabled = false }

      it 'logs the skip at debug level' do
        scaler.run
        expect(logger).to have_received(:debug).with(/Skipped.*disabled/)
      end
    end

    context 'when error occurs' do
      before do
        allow(metrics_collector).to receive(:collect)
          .and_raise(StandardError.new('Connection error'))
      end

      it 'logs the error at error level' do
        scaler.run
        expect(logger).to have_received(:error).with(/Error.*StandardError.*Connection error/)
      end
    end
  end

  describe 'component coordination' do
    it 'passes config to metrics collector' do
      # Force scaler instantiation to trigger the receives
      scaler
      expect(SolidQueueAutoscaler::Metrics).to have_received(:new).with(config: config)
    end

    it 'passes config to decision engine' do
      # Force scaler instantiation to trigger the receives
      scaler
      expect(SolidQueueAutoscaler::DecisionEngine).to have_received(:new).with(config: config)
    end

    it 'uses adapter from config' do
      no_change_decision = SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :no_change, from: 2, to: 2, reason: 'ok'
      )
      allow(decision_engine).to receive(:decide).and_return(no_change_decision)
      allow(adapter).to receive(:current_workers).and_return(2)

      scaler.run

      expect(adapter).to have_received(:current_workers)
    end

    it 'passes metrics and current_workers to decision engine' do
      no_change_decision = SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :no_change, from: 2, to: 2, reason: 'ok'
      )
      allow(decision_engine).to receive(:decide).and_return(no_change_decision)
      allow(adapter).to receive(:current_workers).and_return(2)

      scaler.run

      expect(decision_engine).to have_received(:decide).with(
        metrics: metrics_result,
        current_workers: 2
      )
    end

    it 'passes decision.to to adapter.scale' do
      scale_up_decision = SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_up, from: 2, to: 5, reason: 'high queue'
      )
      allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
      allow(adapter).to receive(:current_workers).and_return(2)
      allow(adapter).to receive(:scale).and_return(5)

      scaler.run

      expect(adapter).to have_received(:scale).with(5)
    end
  end

  describe 'with real DecisionEngine' do
    # Don't mock DecisionEngine - use the real one
    let(:real_scaler) do
      # Create scaler without mocking DecisionEngine
      allow(SolidQueueAutoscaler::DecisionEngine).to receive(:new).and_call_original
      described_class.new(config: config)
    end

    context 'scale up scenario' do
      let(:high_queue_metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 150,
          oldest_job_age_seconds: 60.0,
          jobs_per_minute: 50,
          claimed_jobs: 10,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 2,
          queues_breakdown: { 'default' => 150 },
          collected_at: Time.current
        )
      end

      before do
        config.scale_up_queue_depth = 100
        allow(metrics_collector).to receive(:collect).and_return(high_queue_metrics)
        allow(adapter).to receive(:current_workers).and_return(2)
        allow(adapter).to receive(:scale).and_return(3)
      end

      it 'scales up when queue depth exceeds threshold' do
        result = real_scaler.run
        expect(result.scaled?).to be(true)
        expect(result.decision.action).to eq(:scale_up)
        expect(adapter).to have_received(:scale).with(3)
      end
    end

    context 'scale down scenario' do
      let(:low_queue_metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 5,
          oldest_job_age_seconds: 10.0,
          jobs_per_minute: 200,
          claimed_jobs: 1,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 5,
          queues_breakdown: { 'default' => 5 },
          collected_at: Time.current
        )
      end

      before do
        config.scale_down_queue_depth = 10
        config.scale_down_latency_seconds = 30
        allow(metrics_collector).to receive(:collect).and_return(low_queue_metrics)
        allow(adapter).to receive(:current_workers).and_return(5)
        allow(adapter).to receive(:scale).and_return(4)
      end

      it 'scales down when queue is low' do
        result = real_scaler.run
        expect(result.scaled?).to be(true)
        expect(result.decision.action).to eq(:scale_down)
        expect(adapter).to have_received(:scale).with(4)
      end
    end

    context 'at max workers' do
      let(:high_queue_metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 500,
          oldest_job_age_seconds: 600.0,
          jobs_per_minute: 10,
          claimed_jobs: 30,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 10,
          queues_breakdown: { 'default' => 500 },
          collected_at: Time.current
        )
      end

      before do
        config.max_workers = 10
        allow(metrics_collector).to receive(:collect).and_return(high_queue_metrics)
        allow(adapter).to receive(:current_workers).and_return(10)
      end

      it 'does not scale beyond max_workers' do
        result = real_scaler.run
        expect(result.decision.action).to eq(:no_change)
        expect(result.decision.reason).to include('max_workers')
        expect(adapter).not_to have_received(:scale)
      end
    end

    context 'at min workers' do
      let(:idle_metrics) do
        SolidQueueAutoscaler::Metrics::Result.new(
          queue_depth: 0,
          oldest_job_age_seconds: 0.0,
          jobs_per_minute: 0,
          claimed_jobs: 0,
          failed_jobs: 0,
          blocked_jobs: 0,
          active_workers: 1,
          queues_breakdown: {},
          collected_at: Time.current
        )
      end

      before do
        config.min_workers = 1
        allow(metrics_collector).to receive(:collect).and_return(idle_metrics)
        allow(adapter).to receive(:current_workers).and_return(1)
      end

      it 'does not scale below min_workers' do
        result = real_scaler.run
        expect(result.decision.action).to eq(:no_change)
        expect(result.decision.reason).to include('min_workers')
        expect(adapter).not_to have_received(:scale)
      end
    end
  end

  describe 'integration with Kubernetes adapter' do
    let(:k8s_adapter) do
      instance_double(
        SolidQueueAutoscaler::Adapters::Kubernetes,
        current_workers: 3,
        scale: 4,
        name: 'Kubernetes'
      )
    end

    let(:k8s_config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.kubernetes_deployment = 'my-worker'
        c.kubernetes_namespace = 'production'
        c.min_workers = 1
        c.max_workers = 10
        c.scale_up_queue_depth = 100
        c.cooldown_seconds = 120
        c.dry_run = false
        c.enabled = true
        c.logger = logger
        c.adapter = k8s_adapter
      end
    end

    let(:k8s_scaler) { described_class.new(config: k8s_config) }

    let(:scale_up_decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_up,
        from: 3,
        to: 4,
        reason: 'queue_depth high'
      )
    end

    before do
      allow(SolidQueueAutoscaler::AdvisoryLock).to receive(:new).and_return(lock)
      allow(SolidQueueAutoscaler::Metrics).to receive(:new).and_return(metrics_collector)
      allow(SolidQueueAutoscaler::DecisionEngine).to receive(:new).and_return(decision_engine)
      allow(metrics_collector).to receive(:collect).and_return(metrics_result)
      allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
    end

    it 'works with Kubernetes adapter' do
      result = k8s_scaler.run
      expect(result.success?).to be(true)
      expect(k8s_adapter).to have_received(:scale).with(4)
    end

    it 'gets current workers from Kubernetes adapter' do
      k8s_scaler.run
      expect(k8s_adapter).to have_received(:current_workers)
    end
  end

  describe 'multiple consecutive scaling operations' do
    let(:scale_up_decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_up,
        from: 2,
        to: 3,
        reason: 'queue_depth high'
      )
    end

    before do
      config.cooldown_seconds = 1 # Very short cooldown for testing
      allow(metrics_collector).to receive(:collect).and_return(metrics_result)
      allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
      allow(adapter).to receive(:current_workers).and_return(2)
      allow(adapter).to receive(:scale).and_return(3)
    end

    it 'respects cooldown between consecutive operations' do
      # First scaling should succeed
      result1 = scaler.run
      expect(result1.scaled?).to be(true)

      # Second scaling immediately after should be blocked by cooldown
      result2 = scaler.run
      expect(result2.skipped?).to be(true)
      expect(result2.skipped_reason).to include('Cooldown')
    end

    it 'allows scaling after cooldown expires' do
      # First scaling
      result1 = scaler.run
      expect(result1.scaled?).to be(true)

      # Wait for cooldown to expire
      sleep(1.1)

      # Second scaling should succeed
      result2 = scaler.run
      expect(result2.scaled?).to be(true)
    end
  end

  describe 'concurrent scaling protection' do
    it 'only one instance can scale at a time due to advisory lock' do
      no_change_decision = SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :no_change, from: 2, to: 2, reason: 'ok'
      )
      allow(decision_engine).to receive(:decide).and_return(no_change_decision)
      allow(adapter).to receive(:current_workers).and_return(2)

      # First instance acquires lock
      allow(lock).to receive(:try_lock).and_return(true, false)

      result1 = scaler.run
      expect(result1.success?).to be(true)

      # Second instance cannot acquire lock
      result2 = scaler.run
      expect(result2.skipped?).to be(true)
      expect(result2.skipped_reason).to include('Could not acquire advisory lock')
    end
  end

  describe 'dry run mode' do
    let(:scale_up_decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_up,
        from: 2,
        to: 3,
        reason: 'queue_depth high'
      )
    end

    before do
      config.dry_run = true
      allow(metrics_collector).to receive(:collect).and_return(metrics_result)
      allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
      allow(adapter).to receive(:current_workers).and_return(2)
      allow(adapter).to receive(:scale).and_return(3)
    end

    it 'still calls adapter.scale (adapter handles dry run)' do
      scaler.run
      expect(adapter).to have_received(:scale).with(3)
    end

    it 'returns scaled? as true' do
      result = scaler.run
      expect(result.scaled?).to be(true)
    end

    it 'updates cooldown timestamps' do
      described_class.reset_cooldowns!
      scaler.run
      expect(described_class.last_scale_up_at).to be_within(1.second).of(Time.current)
    end
  end

  describe 'configuration without explicit adapter' do
    let(:config_without_adapter) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        c.heroku_api_key = 'test-api-key'
        c.heroku_app_name = 'test-app'
        c.min_workers = 1
        c.max_workers = 10
        c.dry_run = true
        c.enabled = true
        c.logger = logger
        # NOTE: adapter not explicitly set, should use default Heroku adapter
      end
    end

    it 'uses the default adapter from configuration' do
      described_class.new(config: config_without_adapter)

      # The adapter should be a Heroku adapter by default
      expect(config_without_adapter.adapter).to be_a(SolidQueueAutoscaler::Adapters::Heroku)
    end
  end

  describe 'result object completeness' do
    let(:scale_up_decision) do
      SolidQueueAutoscaler::DecisionEngine::Decision.new(
        action: :scale_up,
        from: 2,
        to: 3,
        reason: 'queue_depth high'
      )
    end

    before do
      allow(metrics_collector).to receive(:collect).and_return(metrics_result)
      allow(decision_engine).to receive(:decide).and_return(scale_up_decision)
      allow(adapter).to receive(:current_workers).and_return(2)
      allow(adapter).to receive(:scale).and_return(3)
    end

    it 'includes all expected fields on success' do
      result = scaler.run

      expect(result.success).to be(true)
      expect(result.decision).to eq(scale_up_decision)
      expect(result.metrics).to eq(metrics_result)
      expect(result.error).to be_nil
      expect(result.skipped_reason).to be_nil
      expect(result.executed_at).to be_present
    end

    it 'includes all expected fields on error' do
      allow(metrics_collector).to receive(:collect)
        .and_raise(StandardError.new('Test error'))

      result = scaler.run

      expect(result.success).to be(false)
      expect(result.decision).to be_nil
      expect(result.metrics).to be_nil
      expect(result.error).to be_a(StandardError)
      expect(result.skipped_reason).to be_nil
      expect(result.executed_at).to be_present
    end

    it 'includes all expected fields when skipped' do
      config.enabled = false

      result = scaler.run

      expect(result.success).to be(true)
      expect(result.decision).to be_nil
      expect(result.metrics).to be_nil
      expect(result.error).to be_nil
      expect(result.skipped_reason).to be_present
      expect(result.executed_at).to be_present
    end
  end
end
