# frozen_string_literal: true

workers         ENV["WEB_CONCURRENCY"]   || 6
threads_count = ENV["RAILS_MAX_THREADS"] || 7
threads threads_count, threads_count

port        ENV["PORT"]     || 3000
environment ENV["RACK_ENV"] || "development"

before_fork do
  MetricsClient.close
end

before_worker_boot do
  ActiveRecord::Base.establish_connection
end
