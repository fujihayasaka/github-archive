# frozen_string_literal: true

# This worker is dedicated for jobs related to graph updates. It was noticed
# that processing of these jobs can be delayed by other, more intensive jobs,
# and to avoid them idling, we've split them out into a separate worker pool.

worker_factory do |queues|
  Aqueduct::Rails::ResquedWorkerAdapter.new(*queues)
end

# More information about the options for working on queues can be found at https://github.com/spraints/resqued#configuring-workers
worker_pool ENV.fetch("AQUEDUCT_WORKER_PROCESS_COUNT", 6).to_i

queue "actions_dynamic_workflow_p4"
queue "actions_dynamic_workflow_p5"
queue "graph_onboard_repository"

before_fork do
  require "./config/environment.rb"
  Rails.application.eager_load!
  ActiveRecord::Base.connection.disconnect!
end

after_fork do |worker|
  ActiveRecord::Base.establish_connection
  worker.cant_fork = true
end

after_exit do |worker_summary|
  tags = ["worker_type:aqueduct_worker", "app:#{Aqueduct.app}"]
  tags += ["exit_status:#{worker_summary.process_status.exitstatus}"] if worker_summary.process_status.exited?
  if worker_summary.process_status.signaled?
    signal_name = Signal.signame(worker_summary.process_status.termsig)
    tags += ["signal:#{signal_name}"]
  end
  MetricsClient.timing("aqueduct.resqued.worker.alive_time_ms",
                       worker_summary.alive_time_sec * 1000, tags: tags)
end
