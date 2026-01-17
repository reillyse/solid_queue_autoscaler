# frozen_string_literal: true

require 'platform-api'

module SolidQueueAutoscaler
  module Adapters
    # Heroku adapter using the Heroku Platform API.
    #
    # This is the default adapter for the autoscaler.
    #
    # Configuration:
    # - heroku_api_key: Heroku API key (or HEROKU_API_KEY env var)
    # - heroku_app_name: Heroku app name (or HEROKU_APP_NAME env var)
    # - process_type: Dyno process type to scale (default: 'worker')
    #
    # @example
    #   SolidQueueAutoscaler.configure do |config|
    #     config.heroku_api_key = ENV['HEROKU_API_KEY']
    #     config.heroku_app_name = ENV['HEROKU_APP_NAME']
    #     config.process_type = 'worker'
    #   end
    class Heroku < Base
      # Retry configuration for transient network errors
      MAX_RETRIES = 3
      RETRY_DELAYS = [1, 2, 4].freeze # Exponential backoff in seconds

      # Errors that are safe to retry (transient network issues)
      RETRYABLE_ERRORS = [
        Excon::Error::Timeout,
        Excon::Error::Socket,
        Excon::Error::HTTPStatus
      ].freeze

      def current_workers
        with_retry do
          formation = client.formation.info(app_name, process_type)
          formation['quantity']
        end
      rescue Excon::Error => e
        raise HerokuAPIError.new(
          "Failed to get formation info: #{e.message}",
          status_code: e.respond_to?(:response) ? e.response&.status : nil,
          response_body: e.respond_to?(:response) ? e.response&.body : nil
        )
      end

      def scale(quantity)
        if dry_run?
          log_dry_run("Would scale #{process_type} to #{quantity} dynos")
          return quantity
        end

        with_retry do
          client.formation.update(app_name, process_type, { quantity: quantity })
        end
        quantity
      rescue Excon::Error => e
        raise HerokuAPIError.new(
          "Failed to scale #{process_type} to #{quantity}: #{e.message}",
          status_code: e.respond_to?(:response) ? e.response&.status : nil,
          response_body: e.respond_to?(:response) ? e.response&.body : nil
        )
      end

      def name
        'Heroku'
      end

      def configuration_errors
        errors = []
        errors << 'heroku_api_key is required' if api_key.nil? || api_key.empty?
        errors << 'heroku_app_name is required' if app_name.nil? || app_name.empty?
        errors
      end

      # Returns the list of all formations for the app.
      #
      # @return [Array<Hash>] formation info hashes
      def formation_list
        client.formation.list(app_name)
      rescue Excon::Error => e
        raise HerokuAPIError.new(
          "Failed to list formations: #{e.message}",
          status_code: e.respond_to?(:response) ? e.response&.status : nil,
          response_body: e.respond_to?(:response) ? e.response&.body : nil
        )
      end

      private

      # Executes a block with retry logic for transient network errors.
      # Uses exponential backoff: 1s, 2s, 4s delays between retries.
      def with_retry
        attempts = 0
        begin
          attempts += 1
          yield
        rescue *RETRYABLE_ERRORS => e
          if attempts < MAX_RETRIES && retryable_error?(e)
            delay = RETRY_DELAYS[attempts - 1] || RETRY_DELAYS.last
            logger&.warn("[Autoscaler] Heroku API error (attempt #{attempts}/#{MAX_RETRIES}), retrying in #{delay}s: #{e.message}")
            sleep(delay)
            retry
          end
          raise
        end
      end

      # Determines if an error should be retried.
      # Retries timeouts and 5xx errors, but not 4xx client errors.
      def retryable_error?(error)
        return true unless error.respond_to?(:response) && error.response

        status = error.response.status
        return true if status.nil?

        # Retry server errors (5xx), not client errors (4xx)
        status >= 500 || status == 429 # Also retry rate limiting
      end

      def client
        @client ||= PlatformAPI.connect_oauth(api_key)
      end

      def api_key
        config.heroku_api_key
      end

      def app_name
        config.heroku_app_name
      end

      def process_type
        config.process_type
      end
    end
  end
end
