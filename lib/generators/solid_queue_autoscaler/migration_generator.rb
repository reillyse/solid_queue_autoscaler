# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module SolidQueueAutoscaler
  module Generators
    class MigrationGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      class_option :database, type: :string, default: nil,
                   desc: 'Specify database for multi-database setups (e.g., --database=queue)'

      desc 'Creates migrations for SolidQueueAutoscaler tables'

      def create_migration_files
        detected_config = detect_database_config
        migration_dir = determine_migration_directory(detected_config)
        db_name = effective_database_name(detected_config)

        # Show what we detected
        print_detection_info(detected_config, migration_dir)

        # Create state table migration
        migration_template 'create_solid_queue_autoscaler_state.rb.erb',
                           "#{migration_dir}/create_solid_queue_autoscaler_state.rb"

        # Create events table migration
        migration_template 'create_solid_queue_autoscaler_events.rb.erb',
                           "#{migration_dir}/create_solid_queue_autoscaler_events.rb"

        print_instructions(migration_dir, db_name)
      end

      private

      # Detect database configuration for SolidQueue.
      # Returns a hash with :database_name, :migrations_path, :is_multi_db.
      def detect_database_config
        result = { database_name: nil, migrations_path: nil, is_multi_db: false }

        # Check if Rails database config is available
        return result unless defined?(Rails) && Rails.application

        db_configs = Rails.application.config.database_configuration
        env_config = db_configs[Rails.env.to_s] || {}

        # Look for a 'queue' database configuration (Rails multi-DB naming convention).
        # SolidQueue typically uses 'queue' as the database name.
        queue_config = find_queue_database_config(env_config)

        if queue_config
          result[:is_multi_db] = true
          result[:database_name] = queue_config[:name]
          result[:migrations_path] = queue_config[:migrations_path]
        end

        result
      rescue StandardError => e
        say '  (Could not detect database config: ' + e.message + ')', :yellow
        { database_name: nil, migrations_path: nil, is_multi_db: false }
      end

      # Find the queue database configuration from environment config.
      def find_queue_database_config(env_config)
        # Rails 7+ multi-database format: { 'primary' => {...}, 'queue' => {...} }
        # Look for common queue database names.
        queue_db_names = %w[queue solid_queue queue_database]

        queue_db_names.each do |db_name|
          if env_config[db_name].is_a?(Hash)
            config = env_config[db_name]
            migrations_path = normalize_migrations_path(config['migrations_paths'], db_name)
            return { name: db_name, migrations_path: migrations_path }
          end
        end

        # Check if any database config has migrations_paths containing 'queue'.
        env_config.each do |name, config|
          next unless config.is_a?(Hash)
          next if name == 'primary' # Skip primary database

          migrations_paths = config['migrations_paths']
          path_str = normalize_migrations_path(migrations_paths, name)
          if path_str.include?('queue')
            return { name: name, migrations_path: path_str }
          end
        end

        nil
      end

      # Normalize migrations_paths which can be a string or array.
      def normalize_migrations_path(migrations_paths, db_name)
        case migrations_paths
        when String
          migrations_paths
        when Array
          migrations_paths.first || "db/#{db_name}_migrate"
        else
          "db/#{db_name}_migrate"
        end
      end

      # Determine the migration directory to use.
      def determine_migration_directory(detected_config)
        # 1. Explicit --database option takes precedence
        if options[:database]
          return 'db/' + options[:database] + '_migrate'
        end

        # 2. If we detected a queue database with migrations_path, use it
        if detected_config[:is_multi_db] && detected_config[:migrations_path]
          return detected_config[:migrations_path]
        end

        # 3. Default to standard migrate directory
        'db/migrate'
      end

      # Get the effective database name for running migrations.
      def effective_database_name(detected_config)
        return options[:database] if options[:database]
        return detected_config[:database_name] if detected_config[:is_multi_db]

        nil
      end

      def print_detection_info(detected_config, migration_dir)
        say ''

        if options[:database]
          say '📁 Using specified database: ' + options[:database], :green
        elsif detected_config[:is_multi_db]
          say '📁 Auto-detected multi-database setup!', :green
          say '   Database: ' + detected_config[:database_name].to_s, :green
          say '   Migration path: ' + detected_config[:migrations_path].to_s, :green
        else
          say '📁 Using standard migration directory', :green

          # Runtime check: warn if SolidQueue appears to use separate connection
          if solidqueue_uses_separate_connection?
            say ''
            say '⚠️  Warning: SolidQueue appears to use a separate database connection!', :yellow
            say '   But we could not detect the migrations_paths from database.yml.', :yellow
            say '   If tables end up in the wrong database, re-run with:', :yellow
            say '   rails g solid_queue_autoscaler:migration --database=queue', :yellow
            say ''
          end
        end

        say '   Placing migrations in: ' + migration_dir + '/', :blue
        say ''
      end

      # Check at runtime if SolidQueue uses a separate database connection.
      def solidqueue_uses_separate_connection?
        return false unless defined?(SolidQueue::Record)
        return false unless SolidQueue::Record.respond_to?(:connection)

        sq_pool = SolidQueue::Record.connection_pool
        ar_pool = ActiveRecord::Base.connection_pool

        sq_pool.db_config.database != ar_pool.db_config.database
      rescue StandardError
        false
      end

      def print_instructions(migration_dir, db_name)
        say '✅ Migrations generated successfully!', :green
        say ''
        say '📖 To run the migrations:', :blue

        if db_name
          # Multi-database setup
          say '   rails db:migrate:' + db_name.to_s, :cyan
          say ''
          say '   Or if that does not work:', :blue
          say '   DATABASE=' + db_name.to_s + ' rails db:migrate', :cyan
        elsif migration_dir != 'db/migrate'
          # Custom migration directory without detected database name
          db_from_path = migration_dir.sub('db/', '').sub('_migrate', '')
          say '   rails db:migrate:' + db_from_path, :cyan
        else
          # Standard single-database
          say '   rails db:migrate', :cyan
        end

        say ''
        say '🔍 To verify setup after migration:', :blue
        say '   SolidQueueAutoscaler.verify_setup!', :cyan
        say ''
      end

      def migration_version
        return unless defined?(ActiveRecord::VERSION)

        '[' + ActiveRecord::VERSION::MAJOR.to_s + '.' +
          ActiveRecord::VERSION::MINOR.to_s + ']'
      end
    end
  end
end
