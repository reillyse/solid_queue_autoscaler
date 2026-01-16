# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module SolidQueueAutoscaler
  module Generators
    # Generator for the dashboard migrations.
    # Creates the scale events table for tracking autoscaler history.
    #
    # @example Run the generator
    #   rails generate solid_queue_autoscaler:dashboard
    class DashboardGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc 'Creates migrations for SolidQueueAutoscaler dashboard (events table)'

      def create_migration_file
        migration_template 'create_solid_queue_autoscaler_events.rb.erb',
                           'db/migrate/create_solid_queue_autoscaler_events.rb'
      end

      def show_post_install
        say ''
        say '=== Solid Queue Autoscaler Dashboard Setup ==='
        say ''
        say 'Next steps:'
        say '  1. Run migrations: rails db:migrate'
        say '  2. Mount the dashboard in config/routes.rb:'
        say ''
        say '     mount SolidQueueAutoscaler::Dashboard::Engine => "/autoscaler"'
        say ''
        say '  3. For authentication, wrap in a constraint:'
        say ''
        say '     authenticate :user, ->(u) { u.admin? } do'
        say '       mount SolidQueueAutoscaler::Dashboard::Engine => "/autoscaler"'
        say '     end'
        say ''
        say 'View the dashboard at: /autoscaler'
        say ''
      end

      private

      def migration_version
        return unless defined?(ActiveRecord::VERSION)

        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
