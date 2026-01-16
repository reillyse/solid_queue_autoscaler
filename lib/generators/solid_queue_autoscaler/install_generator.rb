# frozen_string_literal: true

require 'rails/generators'

module SolidQueueAutoscaler
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc 'Creates a SolidQueueAutoscaler initializer'

      def copy_initializer
        template 'initializer.rb', 'config/initializers/solid_queue_autoscaler.rb'
      end

      def show_readme
        readme 'README' if behavior == :invoke
      end
    end
  end
end
