# frozen_string_literal: true

worker_factory do |queues|
  Aqueduct::Rails::ResquedWorkerAdapter.new(*queues)
end

# More information about the options for working on queues can be found at https://github.com/spraints/resqued#configuring-workers
worker_pool ENV.fetch("AQUEDUCT_WORKER_PROCESS_COUNT", 6).to_i

queue "default"
queue "scheduled_updates", count: 2
queue "update_pull_request"
queue "active_storage", count: 2
queue "actions_dynamic_workflow_p1"
queue "actions_dynamic_workflow_p2"
# because we want to be able to effectively throttle this queue, limit the number of workers.
queue "actions_dynamic_workflow_p3", count: 1
queue "autofix_job"
queue "db_cleanup", count: 1

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
