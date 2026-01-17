# frozen_string_literal: true

RSpec.describe SolidQueueAutoscaler::Adapters::Kubernetes do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil) }

  let(:config) do
    SolidQueueAutoscaler::Configuration.new.tap do |c|
      c.kubernetes_deployment = 'my-worker'
      c.kubernetes_namespace = 'production'
      c.kubernetes_context = 'my-cluster'
      c.dry_run = false
      c.logger = logger
    end
  end

  subject(:adapter) { described_class.new(config: config) }

  # Mock deployment object returned by kubeclient
  let(:deployment_spec) { double('spec', replicas: 3) }
  let(:deployment) { double('deployment', spec: deployment_spec) }
  let(:apps_client) { instance_double('Kubeclient::Client') }

  before do
    # Prevent actual kubeclient loading and client creation
    allow(adapter).to receive(:apps_client).and_return(apps_client)
  end

  describe '#name' do
    it 'returns Kubernetes' do
      expect(adapter.name).to eq('Kubernetes')
    end
  end

  describe '#configuration_errors' do
    context 'with valid configuration' do
      it 'returns empty array' do
        expect(adapter.configuration_errors).to be_empty
      end
    end

    context 'with missing deployment name' do
      before { config.kubernetes_deployment = nil }

      it 'returns error message' do
        expect(adapter.configuration_errors).to include('kubernetes_deployment is required')
      end
    end

    context 'with empty deployment name' do
      before { config.kubernetes_deployment = '' }

      it 'returns error message' do
        expect(adapter.configuration_errors).to include('kubernetes_deployment is required')
      end
    end

    context 'with empty namespace' do
      before { config.kubernetes_namespace = '' }

      it 'returns error message' do
        expect(adapter.configuration_errors).to include('kubernetes_namespace is required')
      end
    end

    context 'with both deployment and namespace empty' do
      before do
        config.kubernetes_deployment = ''
        config.kubernetes_namespace = ''
      end

      it 'returns both error messages' do
        errors = adapter.configuration_errors
        expect(errors).to include('kubernetes_deployment is required')
        expect(errors).to include('kubernetes_namespace is required')
      end
    end
  end

  describe '#configured?' do
    context 'with valid configuration' do
      it 'returns true' do
        expect(adapter.configured?).to be(true)
      end
    end

    context 'with missing deployment name' do
      before { config.kubernetes_deployment = nil }

      it 'returns false' do
        expect(adapter.configured?).to be(false)
      end
    end
  end

  describe '#current_workers' do
    context 'when API call succeeds' do
      before do
        allow(apps_client).to receive(:get_deployment)
          .with('my-worker', 'production')
          .and_return(deployment)
      end

      it 'returns the current replica count' do
        expect(adapter.current_workers).to eq(3)
      end

      it 'calls the Kubernetes API with correct parameters' do
        adapter.current_workers
        expect(apps_client).to have_received(:get_deployment).with('my-worker', 'production')
      end
    end

    context 'when API call fails' do
      before do
        allow(apps_client).to receive(:get_deployment)
          .and_raise(StandardError.new('Connection refused'))
      end

      it 'raises KubernetesAPIError' do
        expect { adapter.current_workers }
          .to raise_error(SolidQueueAutoscaler::KubernetesAPIError, /Failed to get deployment info/)
      end

      it 'includes the original error message' do
        expect { adapter.current_workers }
          .to raise_error(SolidQueueAutoscaler::KubernetesAPIError, /Connection refused/)
      end
    end

    context 'when deployment not found' do
      before do
        allow(apps_client).to receive(:get_deployment)
          .and_raise(StandardError.new('deployments "my-worker" not found'))
      end

      it 'raises KubernetesAPIError' do
        expect { adapter.current_workers }
          .to raise_error(SolidQueueAutoscaler::KubernetesAPIError, /not found/)
      end
    end
  end

  describe '#scale' do
    context 'when dry-run mode is disabled' do
      before do
        config.dry_run = false
        allow(apps_client).to receive(:patch_deployment)
          .and_return(deployment)
      end

      it 'calls patch_deployment with correct parameters' do
        adapter.scale(5)
        expect(apps_client).to have_received(:patch_deployment)
          .with('my-worker', { spec: { replicas: 5 } }, 'production')
      end

      it 'returns the requested quantity' do
        expect(adapter.scale(5)).to eq(5)
      end

      it 'can scale to zero' do
        adapter.scale(0)
        expect(apps_client).to have_received(:patch_deployment)
          .with('my-worker', { spec: { replicas: 0 } }, 'production')
      end

      it 'can scale to large numbers' do
        adapter.scale(100)
        expect(apps_client).to have_received(:patch_deployment)
          .with('my-worker', { spec: { replicas: 100 } }, 'production')
      end
    end

    context 'when dry-run mode is enabled' do
      before do
        config.dry_run = true
        allow(apps_client).to receive(:patch_deployment)
      end

      it 'does not call the Kubernetes API' do
        adapter.scale(5)
        expect(apps_client).not_to have_received(:patch_deployment)
      end

      it 'returns the requested quantity' do
        expect(adapter.scale(5)).to eq(5)
      end

      it 'logs the dry-run action' do
        adapter.scale(5)
        expect(logger).to have_received(:info).with(/\[DRY RUN\].*scale.*my-worker.*5.*production/)
      end
    end

    context 'when API call fails' do
      before do
        config.dry_run = false
        allow(apps_client).to receive(:patch_deployment)
          .and_raise(StandardError.new('Forbidden: insufficient permissions'))
      end

      it 'raises KubernetesAPIError' do
        expect { adapter.scale(5) }
          .to raise_error(SolidQueueAutoscaler::KubernetesAPIError, /Failed to scale deployment/)
      end

      it 'includes the deployment name in error' do
        expect { adapter.scale(5) }
          .to raise_error(SolidQueueAutoscaler::KubernetesAPIError, /my-worker/)
      end

      it 'includes the target quantity in error' do
        expect { adapter.scale(5) }
          .to raise_error(SolidQueueAutoscaler::KubernetesAPIError, /5/)
      end

      it 'includes the original error message' do
        expect { adapter.scale(5) }
          .to raise_error(SolidQueueAutoscaler::KubernetesAPIError, /Forbidden/)
      end
    end
  end

  describe 'environment variable fallbacks' do
    let(:config) do
      SolidQueueAutoscaler::Configuration.new.tap do |c|
        # Don't set kubernetes_deployment or kubernetes_namespace
        c.dry_run = false
        c.logger = logger
      end
    end

    context 'when K8S_DEPLOYMENT env var is set' do
      around do |example|
        original_deployment = ENV.fetch('K8S_DEPLOYMENT', nil)
        ENV['K8S_DEPLOYMENT'] = 'env-worker'
        example.run
        ENV['K8S_DEPLOYMENT'] = original_deployment
      end

      it 'uses deployment from environment' do
        # Need fresh config that reads from ENV
        fresh_config = SolidQueueAutoscaler::Configuration.new.tap do |c|
          c.dry_run = false
          c.logger = logger
          c.kubernetes_namespace = 'default'
        end
        fresh_adapter = described_class.new(config: fresh_config)
        allow(fresh_adapter).to receive(:apps_client).and_return(apps_client)
        allow(apps_client).to receive(:get_deployment).and_return(deployment)

        fresh_adapter.current_workers
        expect(apps_client).to have_received(:get_deployment).with('env-worker', 'default')
      end
    end

    context 'when K8S_NAMESPACE env var is set' do
      around do |example|
        original_namespace = ENV.fetch('K8S_NAMESPACE', nil)
        ENV['K8S_NAMESPACE'] = 'env-namespace'
        example.run
        ENV['K8S_NAMESPACE'] = original_namespace
      end

      it 'uses namespace from environment' do
        fresh_config = SolidQueueAutoscaler::Configuration.new.tap do |c|
          c.kubernetes_deployment = 'my-worker'
          c.dry_run = false
          c.logger = logger
        end
        fresh_adapter = described_class.new(config: fresh_config)
        allow(fresh_adapter).to receive(:apps_client).and_return(apps_client)
        allow(apps_client).to receive(:get_deployment).and_return(deployment)

        fresh_adapter.current_workers
        expect(apps_client).to have_received(:get_deployment).with('my-worker', 'env-namespace')
      end
    end
  end

  describe 'in-cluster detection' do
    # Create a fresh adapter that we can test client building on
    let(:fresh_adapter) { described_class.new(config: config) }

    context 'when running inside a Kubernetes pod' do
      before do
        allow(File).to receive(:exist?)
          .with('/var/run/secrets/kubernetes.io/serviceaccount/token')
          .and_return(true)
      end

      it 'detects in-cluster environment' do
        expect(fresh_adapter.send(:in_cluster?)).to be(true)
      end
    end

    context 'when running outside a Kubernetes cluster' do
      before do
        allow(File).to receive(:exist?)
          .with('/var/run/secrets/kubernetes.io/serviceaccount/token')
          .and_return(false)
      end

      it 'detects non-cluster environment' do
        expect(fresh_adapter.send(:in_cluster?)).to be(false)
      end
    end
  end

  describe 'client building' do
    let(:fresh_adapter) { described_class.new(config: config) }

    context 'when in-cluster' do
      let(:mock_kubeclient) { class_double('Kubeclient::Client').as_stubbed_const }

      before do
        allow(File).to receive(:exist?)
          .with('/var/run/secrets/kubernetes.io/serviceaccount/token')
          .and_return(true)
        allow(fresh_adapter).to receive(:require).with('kubeclient')
        allow(mock_kubeclient).to receive(:new).and_return(apps_client)
        stub_const('OpenSSL::SSL::VERIFY_PEER', 1)
      end

      it 'builds client with in-cluster configuration' do
        # Set up environment variables for in-cluster
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('KUBERNETES_SERVICE_HOST').and_return('10.0.0.1')
        allow(ENV).to receive(:[]).with('KUBERNETES_SERVICE_PORT').and_return('443')

        fresh_adapter.send(:build_apps_client)

        expect(mock_kubeclient).to have_received(:new).with(
          'https://10.0.0.1:443/apis/apps/v1',
          'v1',
          hash_including(
            auth_options: hash_including(:bearer_token_file),
            ssl_options: hash_including(:ca_file)
          )
        )
      end
    end

    context 'when using kubeconfig' do
      let(:mock_kubeclient) { class_double('Kubeclient::Client').as_stubbed_const }
      let(:mock_config_class) { class_double('Kubeclient::Config').as_stubbed_const }
      let(:mock_kubeconfig) { instance_double('Kubeclient::Config') }
      let(:mock_context) do
        double('context',
               api_endpoint: 'https://my-cluster.example.com',
               ssl_options: { verify_ssl: 1 },
               auth_options: { bearer_token: 'token123' })
      end

      before do
        allow(File).to receive(:exist?)
          .with('/var/run/secrets/kubernetes.io/serviceaccount/token')
          .and_return(false)
        allow(fresh_adapter).to receive(:require).with('kubeclient')
        allow(Dir).to receive(:home).and_return('/home/user')
        allow(mock_config_class).to receive(:read).and_return(mock_kubeconfig)
        allow(mock_kubeconfig).to receive(:context).and_return(mock_context)
        allow(mock_kubeclient).to receive(:new).and_return(apps_client)
      end

      it 'reads kubeconfig from default location' do
        config.kubernetes_kubeconfig = nil
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('KUBECONFIG').and_return(nil)

        fresh_adapter.send(:build_apps_client)

        expect(mock_config_class).to have_received(:read).with('/home/user/.kube/config')
      end

      it 'reads kubeconfig from configured path' do
        config.kubernetes_kubeconfig = '/custom/path/kubeconfig'

        fresh_adapter.send(:build_apps_client)

        expect(mock_config_class).to have_received(:read).with('/custom/path/kubeconfig')
      end

      it 'reads kubeconfig from KUBECONFIG env var' do
        config.kubernetes_kubeconfig = nil
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('KUBECONFIG').and_return('/env/kubeconfig')

        fresh_adapter.send(:build_apps_client)

        expect(mock_config_class).to have_received(:read).with('/env/kubeconfig')
      end

      it 'uses configured context' do
        fresh_adapter.send(:build_apps_client)

        expect(mock_kubeconfig).to have_received(:context).with('my-cluster')
      end

      it 'builds client with kubeconfig settings' do
        fresh_adapter.send(:build_apps_client)

        expect(mock_kubeclient).to have_received(:new).with(
          'https://my-cluster.example.com/apis/apps/v1',
          'v1',
          hash_including(
            ssl_options: { verify_ssl: 1 },
            auth_options: { bearer_token: 'token123' }
          )
        )
      end
    end
  end

  describe 'kubernetes environment helpers' do
    let(:fresh_adapter) { described_class.new(config: config) }

    describe '#kubernetes_host' do
      it 'uses KUBERNETES_SERVICE_HOST env var when set' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('KUBERNETES_SERVICE_HOST').and_return('10.96.0.1')

        expect(fresh_adapter.send(:kubernetes_host)).to eq('10.96.0.1')
      end

      it 'defaults to kubernetes.default.svc when env var not set' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('KUBERNETES_SERVICE_HOST').and_return(nil)

        expect(fresh_adapter.send(:kubernetes_host)).to eq('kubernetes.default.svc')
      end
    end

    describe '#kubernetes_port' do
      it 'uses KUBERNETES_SERVICE_PORT env var when set' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('KUBERNETES_SERVICE_PORT').and_return('6443')

        expect(fresh_adapter.send(:kubernetes_port)).to eq('6443')
      end

      it 'defaults to 443 when env var not set' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('KUBERNETES_SERVICE_PORT').and_return(nil)

        expect(fresh_adapter.send(:kubernetes_port)).to eq('443')
      end
    end
  end

  describe 'retry behavior' do
    before do
      allow(adapter).to receive(:sleep) # Stub sleep to avoid slow tests
    end

    describe 'with transient network errors' do
      context 'when Errno::ECONNREFUSED occurs' do
        it 'retries and succeeds on second attempt' do
          call_count = 0
          allow(apps_client).to receive(:get_deployment) do
            call_count += 1
            if call_count == 1
              raise Errno::ECONNREFUSED.new('Connection refused')
            else
              deployment
            end
          end

          expect(adapter.current_workers).to eq(3)
          expect(apps_client).to have_received(:get_deployment).twice
        end

        it 'logs a warning on retry' do
          call_count = 0
          allow(apps_client).to receive(:get_deployment) do
            call_count += 1
            if call_count == 1
              raise Errno::ECONNREFUSED.new('Connection refused')
            else
              deployment
            end
          end

          adapter.current_workers
          expect(logger).to have_received(:warn).with(/Kubernetes API error.*attempt 1\/3.*retrying/)
        end
      end

      context 'when Errno::ETIMEDOUT occurs' do
        it 'retries and succeeds on second attempt' do
          call_count = 0
          allow(apps_client).to receive(:get_deployment) do
            call_count += 1
            if call_count == 1
              raise Errno::ETIMEDOUT.new('Connection timed out')
            else
              deployment
            end
          end

          expect(adapter.current_workers).to eq(3)
          expect(apps_client).to have_received(:get_deployment).twice
        end
      end

      context 'when Errno::ECONNRESET occurs' do
        it 'retries and succeeds on second attempt' do
          call_count = 0
          allow(apps_client).to receive(:get_deployment) do
            call_count += 1
            if call_count == 1
              raise Errno::ECONNRESET.new('Connection reset')
            else
              deployment
            end
          end

          expect(adapter.current_workers).to eq(3)
          expect(apps_client).to have_received(:get_deployment).twice
        end
      end

      context 'when Net::OpenTimeout occurs' do
        it 'retries and succeeds on second attempt' do
          call_count = 0
          allow(apps_client).to receive(:get_deployment) do
            call_count += 1
            if call_count == 1
              raise Net::OpenTimeout.new('Open timeout')
            else
              deployment
            end
          end

          expect(adapter.current_workers).to eq(3)
          expect(apps_client).to have_received(:get_deployment).twice
        end
      end

      context 'when Net::ReadTimeout occurs' do
        it 'retries and succeeds on second attempt' do
          call_count = 0
          allow(apps_client).to receive(:get_deployment) do
            call_count += 1
            if call_count == 1
              raise Net::ReadTimeout.new('Read timeout')
            else
              deployment
            end
          end

          expect(adapter.current_workers).to eq(3)
          expect(apps_client).to have_received(:get_deployment).twice
        end
      end

      context 'when SocketError occurs' do
        it 'retries and succeeds on second attempt' do
          call_count = 0
          allow(apps_client).to receive(:get_deployment) do
            call_count += 1
            if call_count == 1
              raise SocketError.new('Socket error')
            else
              deployment
            end
          end

          expect(adapter.current_workers).to eq(3)
          expect(apps_client).to have_received(:get_deployment).twice
        end
      end
    end

    describe 'exponential backoff' do
      it 'uses delays of 1s, 2s, 4s between retries' do
        call_count = 0
        allow(apps_client).to receive(:get_deployment) do
          call_count += 1
          if call_count < 4
            raise Errno::ECONNREFUSED.new('Connection refused')
          else
            deployment
          end
        end

        # Should fail after 3 retries
        expect { adapter.current_workers }.to raise_error(SolidQueueAutoscaler::KubernetesAPIError)

        # Verify sleep was called with correct backoff delays
        expect(adapter).to have_received(:sleep).with(1).ordered
        expect(adapter).to have_received(:sleep).with(2).ordered
      end
    end

    describe 'max retries' do
      it 'raises error after 3 failed attempts' do
        allow(apps_client).to receive(:get_deployment)
          .and_raise(Errno::ECONNREFUSED.new('Persistent connection refused'))

        expect { adapter.current_workers }.to raise_error(SolidQueueAutoscaler::KubernetesAPIError)
        expect(apps_client).to have_received(:get_deployment).exactly(3).times
      end

      it 'logs warning for each retry attempt' do
        allow(apps_client).to receive(:get_deployment)
          .and_raise(Errno::ETIMEDOUT.new('Timeout'))

        expect { adapter.current_workers }.to raise_error(SolidQueueAutoscaler::KubernetesAPIError)
        expect(logger).to have_received(:warn).with(/attempt 1\/3/).once
        expect(logger).to have_received(:warn).with(/attempt 2\/3/).once
      end
    end

    describe 'non-retryable errors' do
      it 'does NOT retry on generic StandardError' do
        allow(apps_client).to receive(:get_deployment)
          .and_raise(StandardError.new('Deployment not found'))

        expect { adapter.current_workers }.to raise_error(SolidQueueAutoscaler::KubernetesAPIError)
        expect(apps_client).to have_received(:get_deployment).once
      end

      it 'does NOT retry on ArgumentError' do
        allow(apps_client).to receive(:get_deployment)
          .and_raise(ArgumentError.new('Invalid argument'))

        expect { adapter.current_workers }.to raise_error(SolidQueueAutoscaler::KubernetesAPIError)
        expect(apps_client).to have_received(:get_deployment).once
      end
    end

    describe 'retry during scale operation' do
      before do
        config.dry_run = false
      end

      it 'retries scale operation on transient error' do
        call_count = 0
        allow(apps_client).to receive(:patch_deployment) do
          call_count += 1
          if call_count == 1
            raise Net::ReadTimeout.new('Timeout during scale')
          else
            deployment
          end
        end

        expect(adapter.scale(5)).to eq(5)
        expect(apps_client).to have_received(:patch_deployment).twice
      end

      it 'retries on connection reset during scale' do
        call_count = 0
        allow(apps_client).to receive(:patch_deployment) do
          call_count += 1
          if call_count == 1
            raise Errno::ECONNRESET.new('Connection reset')
          else
            deployment
          end
        end

        expect(adapter.scale(10)).to eq(10)
        expect(apps_client).to have_received(:patch_deployment).twice
      end
    end
  end

  describe 'integration with base class' do
    it 'inherits from Base' do
      expect(described_class.superclass).to eq(SolidQueueAutoscaler::Adapters::Base)
    end

    it 'has access to config' do
      expect(adapter.send(:config)).to eq(config)
    end

    it 'has access to logger' do
      expect(adapter.send(:logger)).to eq(logger)
    end

    it 'has access to dry_run?' do
      expect(adapter.send(:dry_run?)).to eq(false)
    end

    it 'can log dry run messages' do
      adapter.send(:log_dry_run, 'test message')
      expect(logger).to have_received(:info).with('[DRY RUN] test message')
    end
  end
end
