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
      def current_workers
        formation = client.formation.info(app_name, process_type)
        formation['quantity']
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

        client.formation.update(app_name, process_type, { quantity: quantity })
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
