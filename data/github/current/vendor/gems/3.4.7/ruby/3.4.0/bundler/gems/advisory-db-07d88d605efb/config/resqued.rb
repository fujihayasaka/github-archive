# frozen_string_literal: true

# Resqued config borrowed largely from dotcom's Resqued configuration in
# config/resqued/github-environment.rb as of 3db4edfc.

before_fork do
  require_relative "environment"

  # We don't need a database connection before forking the workers.
  ActiveRecord::Base.connection_handler.clear_all_connections!(:all)

  # Prune the worker set only on startup to reduce contention on the
  # workers list in redis when worker processes wake up en masse.
  begin
    Resque::Worker.new("*").prune_dead_workers
  rescue Redis::BaseError => error
    Failbot.report!(error)
  end
end

after_fork do |worker|
  ActiveRecord::Base.establish_connection

  # Disable fork-per-job. It adds unnecessary time to each job. Also, we prefer
  # the graceful shutdown behavior that comes with fork_per_job=false.
  worker.fork_per_job = false
end

worker_pool ENV.fetch("WORKER_COUNT", 5).to_i

queue "high"
queue "default"
queue "low"
queue "*"
