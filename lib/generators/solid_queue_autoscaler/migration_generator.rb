# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module SolidQueueAutoscaler
  module Generators
    class MigrationGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc 'Creates the migration for SolidQueueAutoscaler state table'

      def create_migration_file
        migration_template 'create_solid_queue_autoscaler_state.rb.erb',
                           'db/migrate/create_solid_queue_autoscaler_state.rb'
      end

      private

      def migration_version
        return unless defined?(ActiveRecord::VERSION)

        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
