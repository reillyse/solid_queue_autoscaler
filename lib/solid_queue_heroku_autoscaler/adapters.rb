# frozen_string_literal: true

require_relative 'adapters/base'
require_relative 'adapters/heroku'
require_relative 'adapters/kubernetes'

module SolidQueueHerokuAutoscaler
  # Adapters module provides the plugin architecture for different platforms.
  #
  # Built-in adapters:
  # - Adapters::Heroku (default)
  # - Adapters::Kubernetes
  #
  # See Adapters::Base for creating custom adapters.
  module Adapters
    class << self
      # Internal registry of adapter classes keyed by symbolic name.
      #
      # @return [Hash<Symbol, Class>]
      def registry
        @registry ||= {
          heroku: Heroku,
          kubernetes: Kubernetes,
          k8s: Kubernetes
        }
      end

      # Returns all registered adapter classes.
      #
      # @return [Array<Class>]
      def all
        registry.values.uniq
      end

      # Register a new adapter class.
      #
      # @param name [Symbol, String] symbolic name (e.g., :aws_ecs)
      # @param klass [Class] adapter class (subclass of Adapters::Base)
      # @return [void]
      def register(name, klass)
        registry[name.to_sym] = klass
      end

      # Find an adapter by symbolic name or by class short name.
      #
      # @param name [Symbol, String] adapter name (e.g., :heroku, :aws_ecs, 'Heroku')
      # @return [Class, nil] adapter class or nil if not found
      def find(name)
        symbol = name.to_sym
        return registry[symbol] if registry.key?(symbol)

        name_str = name.to_s.downcase
        all.find { |adapter| adapter.name.split('::').last.downcase == name_str }
      end
    end
  end
end
