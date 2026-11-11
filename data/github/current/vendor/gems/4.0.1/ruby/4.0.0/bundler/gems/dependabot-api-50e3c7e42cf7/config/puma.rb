# frozen_string_literal: true

workers Integer(ENV["WEB_CONCURRENCY"] || 6)
threads_count = Integer(ENV["RAILS_MAX_THREADS"] || 7)
threads threads_count, threads_count

preload_app!

port        ENV["PORT"]     || 3000
environment ENV["RACK_ENV"] || "development"

before_fork do
  MetricsClient.close
end

on_worker_boot do
  ActiveRecord::Base.establish_connection
end
