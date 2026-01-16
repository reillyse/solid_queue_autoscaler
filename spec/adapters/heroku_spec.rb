# frozen_string_literal: true

RSpec.describe SolidQueueAutoscaler::Adapters::Heroku do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil) }

  let(:config) do
    SolidQueueAutoscaler::Configuration.new.tap do |c|
      c.heroku_api_key = 'test-api-key-12345'
      c.heroku_app_name = 'my-test-app'
      c.process_type = 'worker'
      c.dry_run = false
      c.logger = logger
    end
  end

  subject(:adapter) { described_class.new(config: config) }

  # Mock PlatformAPI client and formation object
  let(:formation_client) { instance_double('PlatformAPI::Formation') }
  let(:platform_client) { instance_double('PlatformAPI::Client', formation: formation_client) }

  before do
    allow(PlatformAPI).to receive(:connect_oauth).with('test-api-key-12345').and_return(platform_client)
  end

  describe '#name' do
    it 'returns Heroku' do
      expect(adapter.name).to eq('Heroku')
    end
  end

  describe '#configuration_errors' do
    context 'with valid configuration' do
      it 'returns empty array' do
        expect(adapter.configuration_errors).to be_empty
      end
    end

    context 'with missing api key' do
      before { config.heroku_api_key = nil }

      it 'returns error message' do
        expect(adapter.configuration_errors).to include('heroku_api_key is required')
      end
    end

    context 'with empty api key' do
      before { config.heroku_api_key = '' }

      it 'returns error message' do
        expect(adapter.configuration_errors).to include('heroku_api_key is required')
      end
    end

    context 'with missing app name' do
      before { config.heroku_app_name = nil }

      it 'returns error message' do
        expect(adapter.configuration_errors).to include('heroku_app_name is required')
      end
    end

    context 'with empty app name' do
      before { config.heroku_app_name = '' }

      it 'returns error message' do
        expect(adapter.configuration_errors).to include('heroku_app_name is required')
      end
    end

    context 'with both missing' do
      before do
        config.heroku_api_key = nil
        config.heroku_app_name = nil
      end

      it 'returns both error messages' do
        errors = adapter.configuration_errors
        expect(errors).to include('heroku_api_key is required')
        expect(errors).to include('heroku_app_name is required')
      end
    end
  end

  describe '#configured?' do
    context 'with valid configuration' do
      it 'returns true' do
        expect(adapter.configured?).to be(true)
      end
    end

    context 'with missing api key' do
      before { config.heroku_api_key = nil }

      it 'returns false' do
        expect(adapter.configured?).to be(false)
      end
    end

    context 'with missing app name' do
      before { config.heroku_app_name = nil }

      it 'returns false' do
        expect(adapter.configured?).to be(false)
      end
    end
  end

  describe '#current_workers' do
    context 'when API call succeeds' do
      let(:formation_info) do
        {
          'quantity' => 3,
          'size' => 'standard-1x',
          'type' => 'worker',
          'command' => 'bundle exec sidekiq'
        }
      end

      before do
        allow(formation_client).to receive(:info)
          .with('my-test-app', 'worker')
          .and_return(formation_info)
      end

      it 'returns the current dyno count' do
        expect(adapter.current_workers).to eq(3)
      end

      it 'calls the Heroku API with correct parameters' do
        adapter.current_workers
        expect(formation_client).to have_received(:info).with('my-test-app', 'worker')
      end

      it 'connects with the correct API key' do
        adapter.current_workers
        expect(PlatformAPI).to have_received(:connect_oauth).with('test-api-key-12345')
      end
    end

    context 'when API call fails with Excon error' do
      before do
        response = double('response', status: 404,
                                      body: '{"id":"not_found","message":"Couldn\'t find that formation."}')
        error = Excon::Error.new('Not Found')
        error.define_singleton_method(:response) { response }
        allow(formation_client).to receive(:info).and_raise(error)
      end

      it 'raises HerokuAPIError' do
        expect { adapter.current_workers }
          .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Failed to get formation info/)
      end

      it 'includes the original error message' do
        expect { adapter.current_workers }
          .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Not Found/)
      end

      it 'captures status code in error' do
        adapter.current_workers
      rescue SolidQueueAutoscaler::HerokuAPIError => e
        expect(e.status_code).to eq(404)
      end

      it 'captures response body in error' do
        adapter.current_workers
      rescue SolidQueueAutoscaler::HerokuAPIError => e
        expect(e.response_body).to include('not_found')
      end
    end

    context 'when formation does not exist' do
      before do
        allow(formation_client).to receive(:info)
          .and_raise(Excon::Error.new('Formation not found'))
      end

      it 'raises HerokuAPIError' do
        expect { adapter.current_workers }
          .to raise_error(SolidQueueAutoscaler::HerokuAPIError)
      end
    end

    context 'with different process types' do
      before do
        config.process_type = 'sidekiq'
        allow(formation_client).to receive(:info)
          .with('my-test-app', 'sidekiq')
          .and_return({ 'quantity' => 5 })
      end

      it 'uses the configured process type' do
        expect(adapter.current_workers).to eq(5)
        expect(formation_client).to have_received(:info).with('my-test-app', 'sidekiq')
      end
    end
  end

  describe '#scale' do
    context 'when dry-run mode is disabled' do
      before do
        config.dry_run = false
        allow(formation_client).to receive(:update)
          .and_return({ 'quantity' => 5 })
      end

      it 'calls formation.update with correct parameters' do
        adapter.scale(5)
        expect(formation_client).to have_received(:update)
          .with('my-test-app', 'worker', { quantity: 5 })
      end

      it 'returns the requested quantity' do
        expect(adapter.scale(5)).to eq(5)
      end

      it 'can scale to zero' do
        adapter.scale(0)
        expect(formation_client).to have_received(:update)
          .with('my-test-app', 'worker', { quantity: 0 })
      end

      it 'can scale to large numbers' do
        adapter.scale(100)
        expect(formation_client).to have_received(:update)
          .with('my-test-app', 'worker', { quantity: 100 })
      end

      it 'can scale up incrementally' do
        adapter.scale(1)
        expect(formation_client).to have_received(:update)
          .with('my-test-app', 'worker', { quantity: 1 })
      end
    end

    context 'when dry-run mode is enabled' do
      before do
        config.dry_run = true
        allow(formation_client).to receive(:update)
      end

      it 'does not call the Heroku API' do
        adapter.scale(5)
        expect(formation_client).not_to have_received(:update)
      end

      it 'returns the requested quantity' do
        expect(adapter.scale(5)).to eq(5)
      end

      it 'logs the dry-run action' do
        adapter.scale(5)
        expect(logger).to have_received(:info).with(/\[DRY RUN\].*scale.*worker.*5.*dynos/)
      end
    end

    context 'when API call fails' do
      before do
        config.dry_run = false
        allow(formation_client).to receive(:update)
          .and_raise(Excon::Error.new('Forbidden: rate limit exceeded'))
      end

      it 'raises HerokuAPIError' do
        expect { adapter.scale(5) }
          .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Failed to scale worker to 5/)
      end

      it 'includes the process type in error' do
        expect { adapter.scale(5) }
          .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /worker/)
      end

      it 'includes the target quantity in error' do
        expect { adapter.scale(5) }
          .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /5/)
      end

      it 'includes the original error message' do
        expect { adapter.scale(5) }
          .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /rate limit/)
      end
    end

    context 'with different process types' do
      before do
        config.process_type = 'web'
        config.dry_run = false
        allow(formation_client).to receive(:update)
          .and_return({ 'quantity' => 3 })
      end

      it 'uses the configured process type' do
        adapter.scale(3)
        expect(formation_client).to have_received(:update)
          .with('my-test-app', 'web', { quantity: 3 })
      end
    end
  end

  describe '#formation_list' do
    context 'when API call succeeds' do
      let(:formations) do
        [
          { 'type' => 'web', 'quantity' => 2, 'size' => 'standard-1x' },
          { 'type' => 'worker', 'quantity' => 3, 'size' => 'standard-2x' },
          { 'type' => 'clock', 'quantity' => 1, 'size' => 'standard-1x' }
        ]
      end

      before do
        allow(formation_client).to receive(:list)
          .with('my-test-app')
          .and_return(formations)
      end

      it 'returns the list of formations' do
        expect(adapter.formation_list).to eq(formations)
      end

      it 'calls the Heroku API with correct app name' do
        adapter.formation_list
        expect(formation_client).to have_received(:list).with('my-test-app')
      end
    end

    context 'when API call fails' do
      before do
        allow(formation_client).to receive(:list)
          .and_raise(Excon::Error.new('App not found'))
      end

      it 'raises HerokuAPIError' do
        expect { adapter.formation_list }
          .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Failed to list formations/)
      end
    end
  end

  describe 'environment variable fallbacks' do
    context 'when HEROKU_API_KEY env var is set' do
      around do |example|
        original_key = ENV.fetch('HEROKU_API_KEY', nil)
        ENV['HEROKU_API_KEY'] = 'env-api-key-67890'
        example.run
        ENV['HEROKU_API_KEY'] = original_key
      end

      it 'uses API key from environment when not explicitly set' do
        fresh_config = SolidQueueAutoscaler::Configuration.new.tap do |c|
          c.heroku_app_name = 'env-app'
          c.dry_run = false
          c.logger = logger
        end
        fresh_adapter = described_class.new(config: fresh_config)

        allow(PlatformAPI).to receive(:connect_oauth).with('env-api-key-67890').and_return(platform_client)
        allow(formation_client).to receive(:info).and_return({ 'quantity' => 1 })

        fresh_adapter.current_workers
        expect(PlatformAPI).to have_received(:connect_oauth).with('env-api-key-67890')
      end
    end

    context 'when HEROKU_APP_NAME env var is set' do
      around do |example|
        original_app = ENV.fetch('HEROKU_APP_NAME', nil)
        ENV['HEROKU_APP_NAME'] = 'env-app-name'
        example.run
        ENV['HEROKU_APP_NAME'] = original_app
      end

      it 'uses app name from environment when not explicitly set' do
        fresh_config = SolidQueueAutoscaler::Configuration.new.tap do |c|
          c.heroku_api_key = 'test-key'
          c.dry_run = false
          c.logger = logger
        end
        fresh_adapter = described_class.new(config: fresh_config)

        allow(PlatformAPI).to receive(:connect_oauth).and_return(platform_client)
        allow(formation_client).to receive(:info)
          .with('env-app-name', 'worker')
          .and_return({ 'quantity' => 2 })

        fresh_adapter.current_workers
        expect(formation_client).to have_received(:info).with('env-app-name', 'worker')
      end
    end
  end

  describe 'client caching' do
    before do
      allow(formation_client).to receive(:info).and_return({ 'quantity' => 1 })
    end

    it 'reuses the same client instance' do
      adapter.current_workers
      adapter.current_workers
      adapter.current_workers

      expect(PlatformAPI).to have_received(:connect_oauth).once
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

# Integration-style tests using mocked PlatformAPI for error scenarios
RSpec.describe SolidQueueAutoscaler::Adapters::Heroku, 'Error Scenarios' do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil) }

  let(:config) do
    SolidQueueAutoscaler::Configuration.new.tap do |c|
      c.heroku_api_key = 'test-oauth-token'
      c.heroku_app_name = 'my-heroku-app'
      c.process_type = 'worker'
      c.dry_run = false
      c.logger = logger
    end
  end

  subject(:adapter) { described_class.new(config: config) }

  let(:formation_client) { instance_double('PlatformAPI::Formation') }
  let(:platform_client) { instance_double('PlatformAPI::Client', formation: formation_client) }

  before do
    allow(PlatformAPI).to receive(:connect_oauth).and_return(platform_client)
  end

  # Helper to create Excon errors with response details
  # Excon::Error doesn't have a response method by default, so we create a custom error class
  def excon_error_with_response(message, status:, body:)
    response = double('response', status: status, body: body)
    error = Excon::Error.new(message)
    error.define_singleton_method(:response) { response }
    error
  end

  describe 'authentication errors (401)' do
    before do
      allow(formation_client).to receive(:info).and_raise(
        excon_error_with_response(
          'Unauthorized',
          status: 401,
          body: '{"id":"unauthorized","message":"Invalid credentials provided."}'
        )
      )
    end

    it 'raises HerokuAPIError for invalid credentials' do
      expect { adapter.current_workers }
        .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Unauthorized/)
    end

    it 'captures the 401 status code' do
      adapter.current_workers
    rescue SolidQueueAutoscaler::HerokuAPIError => e
      expect(e.status_code).to eq(401)
    end
  end

  describe 'forbidden errors (403)' do
    before do
      allow(formation_client).to receive(:update).and_raise(
        excon_error_with_response(
          'Forbidden',
          status: 403,
          body: '{"id":"forbidden","message":"You do not have access to this resource."}'
        )
      )
    end

    it 'raises HerokuAPIError for forbidden access' do
      expect { adapter.scale(5) }
        .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Forbidden/)
    end

    it 'captures the 403 status code' do
      adapter.scale(5)
    rescue SolidQueueAutoscaler::HerokuAPIError => e
      expect(e.status_code).to eq(403)
    end
  end

  describe 'not found errors (404)' do
    before do
      allow(formation_client).to receive(:info).and_raise(
        excon_error_with_response(
          'Not Found',
          status: 404,
          body: '{"id":"not_found","message":"Couldn\'t find that formation."}'
        )
      )
    end

    it 'raises HerokuAPIError for missing formation' do
      expect { adapter.current_workers }
        .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Not Found/)
    end

    it 'captures the 404 status code' do
      adapter.current_workers
    rescue SolidQueueAutoscaler::HerokuAPIError => e
      expect(e.status_code).to eq(404)
    end
  end

  describe 'validation errors (422)' do
    before do
      allow(formation_client).to receive(:update).and_raise(
        excon_error_with_response(
          'Unprocessable Entity',
          status: 422,
          body: '{"id":"invalid_params","message":"Quantity must be between 0 and 100."}'
        )
      )
    end

    it 'raises HerokuAPIError for invalid parameters' do
      expect { adapter.scale(500) }
        .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Unprocessable Entity/)
    end

    it 'captures the 422 status code' do
      adapter.scale(500)
    rescue SolidQueueAutoscaler::HerokuAPIError => e
      expect(e.status_code).to eq(422)
    end
  end

  describe 'rate limiting (429)' do
    before do
      allow(formation_client).to receive(:info).and_raise(
        excon_error_with_response(
          'Too Many Requests',
          status: 429,
          body: '{"id":"rate_limit","message":"Rate limit exceeded. Please retry in 60 seconds."}'
        )
      )
    end

    it 'raises HerokuAPIError for rate limiting' do
      expect { adapter.current_workers }
        .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Too Many Requests/)
    end

    it 'captures the 429 status code' do
      adapter.current_workers
    rescue SolidQueueAutoscaler::HerokuAPIError => e
      expect(e.status_code).to eq(429)
    end
  end

  describe 'server errors (500)' do
    before do
      allow(formation_client).to receive(:info).and_raise(
        excon_error_with_response(
          'Internal Server Error',
          status: 500,
          body: '{"id":"server_error","message":"An internal server error occurred."}'
        )
      )
    end

    it 'raises HerokuAPIError for server errors' do
      expect { adapter.current_workers }
        .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Internal Server Error/)
    end

    it 'captures the 500 status code' do
      adapter.current_workers
    rescue SolidQueueAutoscaler::HerokuAPIError => e
      expect(e.status_code).to eq(500)
    end
  end

  describe 'service unavailable (503)' do
    before do
      allow(formation_client).to receive(:update).and_raise(
        excon_error_with_response(
          'Service Unavailable',
          status: 503,
          body: '{"id":"service_unavailable","message":"Service temporarily unavailable."}'
        )
      )
    end

    it 'raises HerokuAPIError when service is unavailable' do
      expect { adapter.scale(3) }
        .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Service Unavailable/)
    end

    it 'captures the 503 status code' do
      adapter.scale(3)
    rescue SolidQueueAutoscaler::HerokuAPIError => e
      expect(e.status_code).to eq(503)
    end
  end

  describe 'complete scaling workflow' do
    it 'can check workers, scale up, and verify the new count' do
      # Setup: Initial state returns 2 workers
      allow(formation_client).to receive(:info)
        .with('my-heroku-app', 'worker')
        .and_return({ 'quantity' => 2 }, { 'quantity' => 5 })
      allow(formation_client).to receive(:update)
        .with('my-heroku-app', 'worker', { quantity: 5 })
        .and_return({ 'quantity' => 5 })

      # Check initial state
      expect(adapter.current_workers).to eq(2)

      # Scale up to 5
      expect(adapter.scale(5)).to eq(5)

      # Verify new state (second call to info returns 5)
      # Need to create a new adapter to reset the client cache
      new_adapter = described_class.new(config: config)
      allow(PlatformAPI).to receive(:connect_oauth).and_return(platform_client)
      expect(new_adapter.current_workers).to eq(5)
    end
  end

  describe 'formation list errors' do
    before do
      allow(formation_client).to receive(:list).and_raise(
        excon_error_with_response(
          'App Not Found',
          status: 404,
          body: '{"id":"not_found","message":"Couldn\'t find that app."}'
        )
      )
    end

    it 'raises HerokuAPIError when app not found' do
      expect { adapter.formation_list }
        .to raise_error(SolidQueueAutoscaler::HerokuAPIError, /Failed to list formations/)
    end
  end
end
