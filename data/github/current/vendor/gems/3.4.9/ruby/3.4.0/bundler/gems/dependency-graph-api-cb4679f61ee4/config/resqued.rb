require_relative "../lib/job_queues"

worker_factory do |queues|
  # Add the correct active-job based prefix to the queues
  unless queues.empty? || queues == ["*"]
    Resqued::Worker::DEFAULT_WORKER_FACTORY.call(DependencyGraphAPI::JobQueues.get_prefixed_queues)
  end
end

before_fork do
  require "./config/environment.rb"
  Rails.application.eager_load!
  ActiveRecord::Base.connection.disconnect!
end

worker_pool 12
queue *DependencyGraphAPI::JobQueues.get_plain_queues

after_fork do |worker|
  ActiveRecord::Base.establish_connection
end
