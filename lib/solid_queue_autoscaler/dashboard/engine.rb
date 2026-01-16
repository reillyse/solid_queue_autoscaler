# frozen_string_literal: true

require 'action_controller/railtie'
require 'action_view/railtie'

module SolidQueueAutoscaler
  module Dashboard
    # Rails engine that provides the autoscaler dashboard.
    # Mount at /solid_queue_autoscaler or integrate with Mission Control.
    #
    # @example Mount in routes.rb
    #   mount SolidQueueAutoscaler::Dashboard::Engine => "/solid_queue_autoscaler"
    #
    # @example With authentication
    #   authenticate :user, ->(u) { u.admin? } do
    #     mount SolidQueueAutoscaler::Dashboard::Engine => "/solid_queue_autoscaler"
    #   end
    class Engine < ::Rails::Engine
      isolate_namespace SolidQueueAutoscaler::Dashboard

      # Engine configuration
      config.solid_queue_autoscaler_dashboard = ActiveSupport::OrderedOptions.new
      config.solid_queue_autoscaler_dashboard.title = 'Solid Queue Autoscaler'

      # Capture views path at class definition time (not inside callbacks)
      VIEWS_PATH = File.expand_path('views', __dir__).freeze

      # Configure view paths for the engine
      config.paths['app/views'] << VIEWS_PATH

      initializer 'solid_queue_autoscaler.dashboard.view_paths', before: :add_view_paths do |app|
        # Add views path to the application's view paths
        app.config.paths['app/views'] << VIEWS_PATH
      end

      initializer 'solid_queue_autoscaler.dashboard.integration' do
        # Auto-integrate with Mission Control if available
        ActiveSupport.on_load(:mission_control) do
          # Register with Mission Control's tab system if available
        end
      end
    end

    # Application controller for dashboard
    class ApplicationController < ActionController::Base
      protect_from_forgery with: :exception

      layout 'solid_queue_autoscaler/dashboard/application'

      private

      def autoscaler_status
        @autoscaler_status ||= SolidQueueAutoscaler::Dashboard.status
      end
      helper_method :autoscaler_status

      def events_available?
        @events_available ||= SolidQueueAutoscaler::Dashboard.events_table_available?
      end
      helper_method :events_available?
    end

    # Main dashboard controller
    class DashboardController < ApplicationController
      def index
        @status = autoscaler_status
        @stats = SolidQueueAutoscaler::Dashboard.event_stats(since: 24.hours.ago)
        @recent_events = SolidQueueAutoscaler::Dashboard.recent_events(limit: 10)
      end
    end

    # Events controller
    class EventsController < ApplicationController
      def index
        @worker_filter = params[:worker]
        @events = SolidQueueAutoscaler::Dashboard.recent_events(
          limit: params.fetch(:limit, 100).to_i,
          worker_name: @worker_filter
        )
        @stats = SolidQueueAutoscaler::Dashboard.event_stats(
          since: 24.hours.ago,
          worker_name: @worker_filter
        )
      end
    end

    # Workers controller
    class WorkersController < ApplicationController
      def index
        @workers = autoscaler_status
      end

      def show
        worker_name = params[:id].to_sym
        @worker = SolidQueueAutoscaler::Dashboard.worker_status(worker_name)
        @events = SolidQueueAutoscaler::Dashboard.recent_events(
          limit: 20,
          worker_name: worker_name.to_s
        )
      end

      def scale
        worker_name = params[:id].to_sym
        @result = SolidQueueAutoscaler.scale!(worker_name)
        redirect_to worker_path(worker_name), notice: scale_notice(@result)
      end

      private

      def scale_notice(result)
        if result.success?
          if result.scaled?
            "Scaled from #{result.decision.from} to #{result.decision.to} workers"
          elsif result.skipped?
            "Skipped: #{result.skipped_reason}"
          else
            "No change needed: #{result.decision&.reason}"
          end
        else
          "Error: #{result.error}"
        end
      end
    end
  end
end

# Define routes for the engine
SolidQueueAutoscaler::Dashboard::Engine.routes.draw do
  root to: 'dashboard#index'

  resources :events, only: [:index]

  resources :workers, only: %i[index show] do
    member do
      post :scale
    end
  end
end
