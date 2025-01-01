require "./lib/job_queues"

worker_factory do |queues|
  require "./lib/aqueduct/resqued_worker_adapter.rb"
  Aqueduct::ResquedWorkerAdapter.new(*queues)
end

before_fork do
  require "./config/environment.rb"
  ActiveRecord::Base.connection.disconnect!
end

worker_pool ENV.fetch("AQUEDUCT_WORKER_PROCESS_COUNT", 5).to_i
queue *DependencyGraph.aqueduct.queues

after_fork do |worker|
  ActiveRecord::Base.establish_connection

  # Disable fork-per-job. It adds unnecessary time to each job. Also, we prefer the graceful shutdown behavior that comes with cant_fork=true.
  worker.cant_fork = true
end
