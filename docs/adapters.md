# Adapters Guide

## Overview

The autoscaler uses a plugin architecture to support different infrastructure platforms. By default, it uses the Heroku adapter, but you can create custom adapters for AWS ECS, Google Cloud Run, Kubernetes, or any other platform.

## Built-in Adapters

### Heroku (Default)

The Heroku adapter uses the [Heroku Platform API](https://devcenter.heroku.com/articles/platform-api-reference) to scale worker dynos.

```ruby
# This is the default - no explicit configuration needed
SolidQueueHerokuAutoscaler.configure do |config|
  config.heroku_api_key = ENV['HEROKU_API_KEY']
  config.heroku_app_name = ENV['HEROKU_APP_NAME']
  config.process_type = 'worker'
end
```

### Kubernetes

The Kubernetes adapter uses the [kubeclient gem](https://github.com/ManageIQ/kubeclient) to scale Deployment replicas. It supports both in-cluster configuration (when running inside a pod) and kubeconfig file authentication.

**Requirements:**
- Add `kubeclient` to your Gemfile: `gem 'kubeclient', '~> 4.0'`
- RBAC: Your pod's service account (or kubeconfig user) needs `get` and `patch` permissions on `deployments` in the `apps/v1` API group.

#### In-Cluster Configuration

When running inside a Kubernetes pod, the adapter automatically uses the pod's service account:

```ruby
SolidQueueHerokuAutoscaler.configure do |config|
  config.adapter_class = SolidQueueHerokuAutoscaler::Adapters::Kubernetes
  config.kubernetes_deployment = 'my-worker-deployment'
  config.kubernetes_namespace = 'production'
  
  # Standard autoscaler settings
  config.min_workers = 1
  config.max_workers = 10
end
```

#### Kubeconfig Authentication (Local Development)

When running outside the cluster, the adapter uses your kubeconfig file:

```ruby
SolidQueueHerokuAutoscaler.configure do |config|
  config.adapter_class = SolidQueueHerokuAutoscaler::Adapters::Kubernetes
  config.kubernetes_deployment = 'my-worker-deployment'
  config.kubernetes_namespace = 'default'
  config.kubernetes_context = 'my-cluster-context'  # Optional: specific context
  config.kubernetes_kubeconfig = '/path/to/kubeconfig'  # Optional: defaults to ~/.kube/config
end
```

#### Environment Variables

The Kubernetes adapter also reads from environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `K8S_DEPLOYMENT` | Deployment name | (required) |
| `K8S_NAMESPACE` | Deployment namespace | `default` |
| `K8S_CONTEXT` | Kubeconfig context | (uses current context) |
| `KUBECONFIG` | Path to kubeconfig | `~/.kube/config` |

#### Example RBAC Configuration

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: autoscaler
  namespace: production
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: autoscaler-binding
  namespace: production
subjects:
- kind: ServiceAccount
  name: my-app-service-account
  namespace: production
roleRef:
  kind: Role
  name: autoscaler
  apiGroup: rbac.authorization.k8s.io
```

## Creating Custom Adapters

### Step 1: Create the Adapter Class

Create a new file that inherits from `SolidQueueHerokuAutoscaler::Adapters::Base`:

```ruby
# lib/my_app/autoscaler_adapters/aws_ecs.rb

class AwsEcsAdapter < SolidQueueHerokuAutoscaler::Adapters::Base
  # Required: Get current worker count
  def current_workers
    # Call your infrastructure API
    ecs_client.describe_services(
      cluster: cluster_name,
      services: [service_name]
    ).services.first.running_count
  end

  # Required: Scale to specified quantity
  def scale(quantity)
    # In dry-run mode, just log
    if dry_run?
      log_dry_run("Would scale ECS service to #{quantity} tasks")
      return quantity
    end

    # Call your infrastructure API
    ecs_client.update_service(
      cluster: cluster_name,
      service: service_name,
      desired_count: quantity
    )
    
    quantity
  end

  # Optional: Override adapter name for logging
  def name
    'AWS ECS'
  end

  # Optional: Add configuration validation
  def configuration_errors
    errors = []
    errors << 'aws_cluster is required' if aws_cluster.nil?
    errors << 'aws_service is required' if aws_service.nil?
    errors
  end

  private

  def ecs_client
    @ecs_client ||= Aws::ECS::Client.new
  end

  def cluster_name
    @config.aws_cluster || ENV['AWS_ECS_CLUSTER']
  end

  def service_name
    @config.aws_service || ENV['AWS_ECS_SERVICE']
  end
end
```

### Step 2: Configure the Autoscaler

There are two ways to use your custom adapter:

#### Option A: Set the adapter class

```ruby
SolidQueueHerokuAutoscaler.configure do |config|
  config.adapter_class = AwsEcsAdapter
  
  # Your custom configuration
  config.aws_cluster = ENV['AWS_ECS_CLUSTER']
  config.aws_service = ENV['AWS_ECS_SERVICE']
  
  # Standard autoscaler settings
  config.min_workers = 1
  config.max_workers = 10
end
```

#### Option B: Set a pre-configured adapter instance

```ruby
SolidQueueHerokuAutoscaler.configure do |config|
  # Create adapter with custom initialization
  adapter = AwsEcsAdapter.new(config: config)
  config.adapter = adapter
  
  # Standard autoscaler settings
  config.min_workers = 1
  config.max_workers = 10
end
```

### Step 3: Add Custom Configuration (Optional)

If your adapter needs custom configuration options, you can extend the Configuration class:

```ruby
# config/initializers/autoscaler.rb

# Add custom attributes to Configuration
SolidQueueHerokuAutoscaler::Configuration.class_eval do
  attr_accessor :aws_cluster, :aws_service, :aws_region
end

SolidQueueHerokuAutoscaler.configure do |config|
  config.adapter_class = AwsEcsAdapter
  config.aws_cluster = ENV['AWS_ECS_CLUSTER']
  config.aws_service = ENV['AWS_ECS_SERVICE']
  config.aws_region = ENV['AWS_REGION']
  # ... other config
end
```

## Adapter Interface

### Required Methods

| Method | Return Type | Description |
|--------|-------------|-------------|
| `current_workers` | Integer | Get current worker count |
| `scale(quantity)` | Integer | Scale to quantity, return new count |

### Optional Methods

| Method | Return Type | Description |
|--------|-------------|-------------|
| `name` | String | Adapter name for logging (default: class name) |
| `configured?` | Boolean | Check if adapter is configured (default: configuration_errors.empty?) |
| `configuration_errors` | Array<String> | Return validation errors (default: []) |

### Helper Methods (Available from Base)

| Method | Description |
|--------|-------------|
| `config` | Access configuration object |
| `logger` | Access configured logger |
| `dry_run?` | Check if dry-run mode is enabled |
| `log_dry_run(message)` | Log a dry-run action |

## Example Adapters

### Google Cloud Run

```ruby
class CloudRunAdapter < SolidQueueHerokuAutoscaler::Adapters::Base
  def current_workers
    service = run_client.get_service(service_path)
    service.spec.template.spec.container_concurrency || 1
  end

  def scale(quantity)
    if dry_run?
      log_dry_run("Would scale Cloud Run service to #{quantity} instances")
      return quantity
    end

    # Cloud Run scales automatically, but you can adjust min instances
    run_client.update_service(service_path, {
      spec: {
        template: {
          metadata: {
            annotations: {
              'autoscaling.knative.dev/minScale' => quantity.to_s
            }
          }
        }
      }
    })
    quantity
  end

  def name
    'Cloud Run'
  end

  private

  def run_client
    @run_client ||= Google::Cloud::Run.new
  end

  def service_path
    "projects/#{project_id}/locations/#{region}/services/#{service_name}"
  end

  def project_id
    @config.respond_to?(:gcp_project) ? @config.gcp_project : ENV['GCP_PROJECT']
  end

  def region
    @config.respond_to?(:gcp_region) ? @config.gcp_region : ENV['GCP_REGION']
  end

  def service_name
    @config.respond_to?(:gcp_service) ? @config.gcp_service : ENV['GCP_SERVICE']
  end
end
```

### Render

```ruby
class RenderAdapter < SolidQueueHerokuAutoscaler::Adapters::Base
  def current_workers
    response = http_client.get("/services/#{service_id}")
    JSON.parse(response.body)['numInstances']
  end

  def scale(quantity)
    if dry_run?
      log_dry_run("Would scale Render service to #{quantity} instances")
      return quantity
    end

    http_client.patch("/services/#{service_id}", {
      numInstances: quantity
    })
    quantity
  end

  def name
    'Render'
  end

  def configuration_errors
    errors = []
    errors << 'render_api_key is required' if api_key.nil? || api_key.empty?
    errors << 'render_service_id is required' if service_id.nil? || service_id.empty?
    errors
  end

  private

  def http_client
    @http_client ||= begin
      conn = Faraday.new('https://api.render.com/v1') do |f|
        f.request :json
        f.response :json
        f.headers['Authorization'] = "Bearer #{api_key}"
      end
      conn
    end
  end

  def api_key
    @config.respond_to?(:render_api_key) ? @config.render_api_key : ENV['RENDER_API_KEY']
  end

  def service_id
    @config.respond_to?(:render_service_id) ? @config.render_service_id : ENV['RENDER_SERVICE_ID']
  end
end
```

## Testing Custom Adapters

```ruby
RSpec.describe AwsEcsAdapter do
  let(:config) do
    SolidQueueHerokuAutoscaler::Configuration.new.tap do |c|
      c.aws_cluster = 'test-cluster'
      c.aws_service = 'test-service'
    end
  end

  subject(:adapter) { described_class.new(config: config) }

  describe '#current_workers' do
    it 'returns the current task count' do
      stub_ecs_describe_services(running_count: 3)
      expect(adapter.current_workers).to eq(3)
    end
  end

  describe '#scale' do
    context 'in normal mode' do
      it 'updates the service desired count' do
        stub_ecs_update_service
        expect(adapter.scale(5)).to eq(5)
      end
    end

    context 'in dry-run mode' do
      before { config.dry_run = true }

      it 'does not call the API' do
        expect(adapter.scale(5)).to eq(5)
        # Verify no API call was made
      end
    end
  end

  describe '#configuration_errors' do
    context 'with valid config' do
      it 'returns empty array' do
        expect(adapter.configuration_errors).to be_empty
      end
    end

    context 'with missing cluster' do
      before { config.aws_cluster = nil }

      it 'returns error' do
        expect(adapter.configuration_errors).to include('aws_cluster is required')
      end
    end
  end
end
```

## Packaging as a Gem

If you want to share your adapter, package it as a gem:

```ruby
# solid_queue_autoscaler_aws.gemspec
Gem::Specification.new do |spec|
  spec.name = 'solid_queue_autoscaler_aws'
  spec.version = '0.1.0'
  spec.summary = 'AWS ECS adapter for Solid Queue Autoscaler'
  
  spec.add_dependency 'solid_queue_heroku_autoscaler', '~> 0.1'
  spec.add_dependency 'aws-sdk-ecs', '~> 1.0'
end
```

```ruby
# lib/solid_queue_autoscaler_aws.rb
require 'solid_queue_heroku_autoscaler'
require 'aws-sdk-ecs'

require_relative 'solid_queue_autoscaler_aws/ecs_adapter'

# Register the adapter
SolidQueueHerokuAutoscaler::Adapters.register(:aws_ecs, SolidQueueAutoscalerAws::EcsAdapter)
```

## Troubleshooting

### "NotImplementedError: must implement #current_workers"

Your adapter doesn't implement the required `current_workers` method.

### Configuration errors not showing

Make sure your `configuration_errors` method returns an Array of strings, and that you're calling `validate!` on the configuration.

### Dry-run not working

Check that you're calling `dry_run?` in your `scale` method and returning early:

```ruby
def scale(quantity)
  if dry_run?
    log_dry_run("Would scale to #{quantity}")
    return quantity
  end
  # ... actual scaling
end
```
