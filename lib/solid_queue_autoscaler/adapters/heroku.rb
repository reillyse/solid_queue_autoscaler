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
      # Errors that are safe to retry (transient network issues)
      RETRYABLE_ERRORS = [
        Excon::Error::Timeout,
        Excon::Error::Socket,
        Excon::Error::HTTPStatus
      ].freeze

      def current_workers
        with_retry(RETRYABLE_ERRORS, retryable_check: method(:retryable_error?)) do
          formation = client.formation.info(app_name, process_type)
          formation['quantity']
        end
      rescue Excon::Error => e
        # Handle 404 gracefully - formation doesn't exist means 0 workers
        # This happens when a dyno type is scaled to 0 and removed from formation
        if e.respond_to?(:response) && e.response&.status == 404
          logger&.debug("[Autoscaler] Formation '#{process_type}' not found, treating as 0 workers")
          return 0
        end

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

        with_retry(RETRYABLE_ERRORS, retryable_check: method(:retryable_error?)) do
          client.formation.update(app_name, process_type, { quantity: quantity })
        end
        quantity
      rescue Excon::Error => e
        # Handle 404 by trying to create the formation via batch_update
        # This happens when scaling up a dyno type that was previously scaled to 0
        if e.respond_to?(:response) && e.response&.status == 404
          return create_formation(quantity)
        end

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

      # Creates a formation that doesn't exist using batch_update.
      # This is needed when scaling up a dyno type that was previously scaled to 0.
      #
      # @param quantity [Integer] desired worker count
      # @return [Integer] the new worker count
      # @raise [HerokuAPIError] if the API call fails
      def create_formation(quantity)
        logger&.info("[Autoscaler] Formation '#{process_type}' not found, creating with quantity #{quantity}")

        with_retry(RETRYABLE_ERRORS, retryable_check: method(:retryable_error?)) do
          client.formation.batch_update(app_name, {
            updates: [
              { type: process_type, quantity: quantity }
            ]
          })
        end
        quantity
      rescue Excon::Error => e
        status = e.respond_to?(:response) ? e.response&.status : nil
        
        # 404 from batch_update means the process type doesn't exist in the Procfile
        # This is different from 404 on formation.update (which means scaled to 0)
        if status == 404
          raise HerokuAPIError.new(
            "Process type '#{process_type}' does not exist. " \
            "Verify that '#{process_type}:' is defined in your Procfile. " \
            "Available process types can be viewed with 'heroku ps -a #{app_name}' or in your Procfile. " \
            "The configured process_type must exactly match a Procfile entry.",
            status_code: status,
            response_body: e.respond_to?(:response) ? e.response&.body : nil
          )
        end

        raise HerokuAPIError.new(
          "Failed to create formation #{process_type} with quantity #{quantity}: #{e.message}",
          status_code: status,
          response_body: e.respond_to?(:response) ? e.response&.body : nil
        )
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
