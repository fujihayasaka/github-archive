# frozen_string_literal: true

# We currently have a number of jobs on dedicated queues that are throttled on
# the application-side. This means that these jobs can sit idling for a while,
# and to avoid them hogging resources while other jobs could be processed, we've
# split them out into a separate worker pool. This setup is from our sidekiq
# days, as it has no way to throttle on the server side. Aqueduct _does_ have
# that capability, and we should be able to move these jobs over to using that,
# but in the meantime, to keep churn as low as possible, this exists.

worker_factory do |queues|
  Aqueduct::Rails::ResquedWorkerAdapter.new(*queues)
end

# More information about the options for working on queues can be found at https://github.com/spraints/resqued#configuring-workers
worker_pool ENV.fetch("AQUEDUCT_WORKER_PROCESS_COUNT", 6).to_i

# This will end up looking something like:
queue "create_pull_request_p1"
queue "create_pull_request_p2"
queue "create_pull_request_p3", count: 2
queue "pause_repo"
queue "unpause_repo"

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
