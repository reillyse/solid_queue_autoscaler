# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'active_record'
require 'solid_queue_autoscaler'

# Database setup
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'db/development.sqlite3'
)

# Configure the autoscaler
SolidQueueAutoscaler.configure(:worker) do |config|
  config.adapter = :heroku
  config.heroku_api_key = ENV.fetch('HEROKU_API_KEY', 'test-api-key')
  config.heroku_app_name = ENV.fetch('HEROKU_APP_NAME', 'test-app')
  config.process_type = 'worker'
  config.min_workers = 1
  config.max_workers = 5
  config.job_queue = :autoscaler
  config.dry_run = true
  config.enabled = true
end

SolidQueueAutoscaler.configure(:priority_worker) do |config|
  config.adapter = :heroku
  config.heroku_api_key = ENV.fetch('HEROKU_API_KEY', 'test-api-key')
  config.heroku_app_name = ENV.fetch('HEROKU_APP_NAME', 'test-app')
  config.process_type = 'priority_worker'
  config.min_workers = 1
  config.max_workers = 3
  config.job_queue = :autoscaler
  config.dry_run = true
  config.enabled = true
end

# Routes
get '/' do
  content_type :json
  {
    app: 'SolidQueueAutoscaler Sinatra Test App',
    version: SolidQueueAutoscaler::VERSION,
    workers: SolidQueueAutoscaler.registered_workers
  }.to_json
end

get '/status' do
  content_type :json
  SolidQueueAutoscaler.registered_workers.map do |name|
    config = SolidQueueAutoscaler.config(name)
    {
      worker: name,
      enabled: config.enabled?,
      dry_run: config.dry_run?,
      process_type: config.process_type,
      min_workers: config.min_workers,
      max_workers: config.max_workers,
      adapter: config.adapter.class.name
    }
  end.to_json
end

get '/config/:worker' do
  content_type :json
  worker_name = params[:worker].to_sym
  config = SolidQueueAutoscaler.config(worker_name)
  {
    worker: worker_name,
    enabled: config.enabled?,
    dry_run: config.dry_run?,
    process_type: config.process_type,
    min_workers: config.min_workers,
    max_workers: config.max_workers,
    job_queue: config.job_queue,
    adapter: config.adapter.class.name
  }.to_json
end
