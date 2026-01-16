# frozen_string_literal: true

# Integration tests for the Dashboard Engine view paths
# These tests verify that view files exist in the correct locations.
# This prevents the MissingExactTemplate regression we experienced.
#
# Note: These tests don't require Rails to be loaded - they just verify
# the file structure is correct.

RSpec.describe 'Dashboard Engine View Structure' do
  # Get the gem root directory (spec is at solid_queue_autoscaler/spec/)
  let(:gem_root) { Pathname.new(File.expand_path('..', __dir__)) }
  let(:views_root) { gem_root.join('app', 'views') }

  describe 'app/views directory structure' do
    it 'has app/views directory' do
      expect(views_root).to be_directory
    end

    it 'has solid_queue_autoscaler/dashboard namespace directory' do
      expect(views_root.join('solid_queue_autoscaler', 'dashboard')).to be_directory
    end
  end

  describe 'controller view directories' do
    it 'has dashboard controller views directory' do
      expect(views_root.join('solid_queue_autoscaler/dashboard/dashboard')).to be_directory
    end

    it 'has workers controller views directory' do
      expect(views_root.join('solid_queue_autoscaler/dashboard/workers')).to be_directory
    end

    it 'has events controller views directory' do
      expect(views_root.join('solid_queue_autoscaler/dashboard/events')).to be_directory
    end
  end

  describe 'required view templates' do
    # These are the exact paths Rails will look for with isolate_namespace SolidQueueAutoscaler::Dashboard
    
    it 'has dashboard index view at correct path' do
      path = views_root.join('solid_queue_autoscaler/dashboard/dashboard/index.html.erb')
      expect(path).to exist, "Missing: #{path}\nThis will cause MissingExactTemplate for DashboardController#index"
    end

    it 'has workers index view at correct path' do
      path = views_root.join('solid_queue_autoscaler/dashboard/workers/index.html.erb')
      expect(path).to exist, "Missing: #{path}\nThis will cause MissingExactTemplate for WorkersController#index"
    end

    it 'has workers show view at correct path' do
      path = views_root.join('solid_queue_autoscaler/dashboard/workers/show.html.erb')
      expect(path).to exist, "Missing: #{path}\nThis will cause MissingExactTemplate for WorkersController#show"
    end

    it 'has events index view at correct path' do
      path = views_root.join('solid_queue_autoscaler/dashboard/events/index.html.erb')
      expect(path).to exist, "Missing: #{path}\nThis will cause MissingExactTemplate for EventsController#index"
    end
  end

  describe 'layout template' do
    it 'has dashboard layout at correct path' do
      # Layout path for 'solid_queue_autoscaler/dashboard' layout
      path = views_root.join('layouts/solid_queue_autoscaler/dashboard.html.erb')
      expect(path).to exist, "Missing: #{path}\nThis will cause missing layout error"
    end
  end

  describe 'gemspec includes app directory' do
    let(:gemspec_path) { gem_root.join('solid_queue_autoscaler.gemspec') }

    it 'includes app/**/* in gemspec files' do
      gemspec_content = File.read(gemspec_path)
      expect(gemspec_content).to include('app/**/*'),
        "Gemspec must include 'app/**/*' in files array for views to be packaged with gem"
    end
  end
end

RSpec.describe 'Dashboard Engine Configuration' do
  let(:engine_file) { File.read(File.expand_path('../lib/solid_queue_autoscaler/dashboard/engine.rb', __dir__)) }

  describe 'ApplicationController configuration' do
    it 'uses prepend_view_path for engine views' do
      # The controller must explicitly add view paths due to isolate_namespace behavior
      expect(engine_file).to include('prepend_view_path'),
        "ApplicationController must use prepend_view_path to add engine views. " \
        "Without this, controllers won't find templates (MissingExactTemplate error)"
    end

    it 'uses Engine.root for view path' do
      # Using Engine.root ensures correct path resolution
      expect(engine_file).to include("Engine.root.join('app', 'views')") |
                            include('Engine.root.join("app", "views")'),
        "View path must use Engine.root.join('app', 'views') for correct path resolution"
    end

    it 'sets correct layout' do
      expect(engine_file).to include("layout 'solid_queue_autoscaler/dashboard'"),
        "Layout must be 'solid_queue_autoscaler/dashboard' to match layouts/solid_queue_autoscaler/dashboard.html.erb"
    end
  end

  describe 'isolate_namespace configuration' do
    it 'uses isolate_namespace' do
      expect(engine_file).to include('isolate_namespace SolidQueueAutoscaler::Dashboard'),
        "Engine must use isolate_namespace for proper namespacing"
    end
  end
end
