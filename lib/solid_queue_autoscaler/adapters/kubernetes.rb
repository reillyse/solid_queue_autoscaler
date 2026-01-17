# frozen_string_literal: true

require 'net/http'

module SolidQueueAutoscaler
  module Adapters
    # Kubernetes adapter for scaling Deployment replicas.
    #
    # Uses the kubeclient gem to interact with the Kubernetes API.
    # Supports both in-cluster configuration and kubeconfig file authentication.
    #
    # Configuration:
    # - kubernetes_deployment: Name of the Deployment to scale (or K8S_DEPLOYMENT env var)
    # - kubernetes_namespace: Namespace of the Deployment (default: 'default', or K8S_NAMESPACE env var)
    # - kubernetes_context: Kubeconfig context to use (optional, for kubeconfig auth)
    #
    # @example In-cluster configuration (running inside a pod)
    #   SolidQueueAutoscaler.configure do |config|
    #     config.adapter_class = SolidQueueAutoscaler::Adapters::Kubernetes
    #     config.kubernetes_deployment = 'my-worker'
    #     config.kubernetes_namespace = 'production'
    #   end
    #
    # @example Using kubeconfig (local development)
    #   SolidQueueAutoscaler.configure do |config|
    #     config.adapter_class = SolidQueueAutoscaler::Adapters::Kubernetes
    #     config.kubernetes_deployment = 'my-worker'
    #     config.kubernetes_namespace = 'default'
    #     config.kubernetes_context = 'my-cluster-context'
    #   end
    class Kubernetes < Base
      # Kubernetes API path for apps/v1 group
      APPS_API_VERSION = 'apis/apps/v1'

      # Default timeout for Kubernetes API calls (seconds)
      DEFAULT_TIMEOUT = 30

      # Errors that are safe to retry (transient network issues)
      RETRYABLE_ERRORS = [
        Errno::ECONNREFUSED,
        Errno::ETIMEDOUT,
        Errno::ECONNRESET,
        Net::OpenTimeout,
        Net::ReadTimeout,
        SocketError
      ].freeze

      def current_workers
        with_retry(RETRYABLE_ERRORS) do
          deployment = apps_client.get_deployment(deployment_name, namespace)
          deployment.spec.replicas
        end
      rescue StandardError => e
        raise KubernetesAPIError.new("Failed to get deployment info: #{e.message}", original_error: e)
      end

      def scale(quantity)
        if dry_run?
          log_dry_run("Would scale deployment #{deployment_name} to #{quantity} replicas in namespace #{namespace}")
          return quantity
        end

        with_retry(RETRYABLE_ERRORS) do
          patch_body = { spec: { replicas: quantity } }
          apps_client.patch_deployment(deployment_name, patch_body, namespace)
        end
        quantity
      rescue StandardError => e
        raise KubernetesAPIError.new("Failed to scale deployment #{deployment_name} to #{quantity}: #{e.message}",
                                     original_error: e)
      end

      def name
        'Kubernetes'
      end

      def configuration_errors
        errors = []
        errors << 'kubernetes_deployment is required' if deployment_name.nil? || deployment_name.empty?
        errors << 'kubernetes_namespace is required' if namespace.nil? || namespace.empty?
        errors
      end

      private

      def apps_client
        @apps_client ||= build_apps_client
      end

      def build_apps_client
        require 'kubeclient'

        if in_cluster?
          build_in_cluster_client
        else
          build_kubeconfig_client
        end
      end

      def build_in_cluster_client
        # In-cluster configuration reads from mounted service account
        auth_options = {
          bearer_token_file: '/var/run/secrets/kubernetes.io/serviceaccount/token'
        }

        ssl_options = {
          ca_file: '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
          verify_ssl: OpenSSL::SSL::VERIFY_PEER
        }

        api_endpoint = "https://#{kubernetes_host}:#{kubernetes_port}/#{APPS_API_VERSION}"

        Kubeclient::Client.new(
          api_endpoint,
          'v1',
          auth_options: auth_options,
          ssl_options: ssl_options,
          timeouts: {
            open: DEFAULT_TIMEOUT,
            read: DEFAULT_TIMEOUT
          }
        )
      end

      def build_kubeconfig_client
        kubeconfig_path = config.respond_to?(:kubernetes_kubeconfig) ? config.kubernetes_kubeconfig : nil
        kubeconfig_path ||= ENV['KUBECONFIG'] || File.join(Dir.home, '.kube', 'config')

        kubeconfig = Kubeclient::Config.read(kubeconfig_path)
        context = kubeconfig.context(kubernetes_context)

        api_endpoint = "#{context.api_endpoint}/#{APPS_API_VERSION}"

        Kubeclient::Client.new(
          api_endpoint,
          'v1',
          ssl_options: context.ssl_options,
          auth_options: context.auth_options,
          timeouts: {
            open: DEFAULT_TIMEOUT,
            read: DEFAULT_TIMEOUT
          }
        )
      end

      def in_cluster?
        # Check if running inside a Kubernetes pod by looking for the service account token
        File.exist?('/var/run/secrets/kubernetes.io/serviceaccount/token')
      end

      def kubernetes_host
        ENV['KUBERNETES_SERVICE_HOST'] || 'kubernetes.default.svc'
      end

      def kubernetes_port
        ENV['KUBERNETES_SERVICE_PORT'] || '443'
      end

      def deployment_name
        if config.respond_to?(:kubernetes_deployment)
          config.kubernetes_deployment
        else
          ENV.fetch('K8S_DEPLOYMENT', nil)
        end
      end

      def namespace
        ns = if config.respond_to?(:kubernetes_namespace)
               config.kubernetes_namespace
             else
               ENV.fetch('K8S_NAMESPACE', nil)
             end
        ns || 'default'
      end

      def kubernetes_context
        if config.respond_to?(:kubernetes_context)
          config.kubernetes_context
        else
          ENV.fetch('K8S_CONTEXT', nil)
        end
      end
    end
  end
end
