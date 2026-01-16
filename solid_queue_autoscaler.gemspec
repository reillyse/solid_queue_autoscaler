# frozen_string_literal: true

require_relative 'lib/solid_queue_autoscaler/version'

Gem::Specification.new do |spec|
  spec.name = 'solid_queue_autoscaler'
  spec.version = SolidQueueAutoscaler::VERSION
  spec.authors = ['reillyse']
  spec.email = []

  spec.summary = 'Auto-scale Solid Queue workers on Heroku based on queue metrics'
  spec.description = 'A control plane for Solid Queue on Heroku that automatically scales worker dynos based on queue depth, job latency, and throughput. Uses PostgreSQL advisory locks for singleton behavior and the Heroku Platform API for scaling.'
  spec.homepage = 'https://github.com/reillyse/solid_queue_autoscaler'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob(%w[
                          app/**/*
                          lib/**/*
                          CHANGELOG.md
                          LICENSE.txt
                          README.md
                        ]).reject { |f| File.directory?(f) }

  # Optional: Only required for dashboard
  # spec.add_dependency 'actionpack', '>= 7.0'
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'activerecord', '>= 7.0'
  spec.add_dependency 'activesupport', '>= 7.0'
  spec.add_dependency 'platform-api', '~> 3.0'

  # Optional: Only required if using Kubernetes adapter
  # spec.add_dependency 'kubeclient', '~> 4.0'

  # Development dependencies
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.50'
  spec.add_development_dependency 'webmock', '~> 3.18'
end
