# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("enqueue.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  job = event.payload.fetch(:job)
  job_name = job.class.name.underscore
  queue_name = job.queue_name
  is_retry = job.executions.positive?

  MetricsClient.increment("job.enqueued",
                          tags: { job: job_name, queue: queue_name, retry: is_retry },)
end

ActiveSupport::Notifications.subscribe("enqueue_at.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  job = event.payload.fetch(:job)
  job_name = job.class.name.underscore
  queue_name = job.queue_name
  is_retry = job.executions.positive?

  MetricsClient.increment("job.scheduled",
                          tags: { job: job_name, queue: queue_name, retry: is_retry },)
end

ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  job = event.payload.fetch(:job)
  job_name = job.class.name.underscore
  queue_name = job.queue_name
  is_retry = job.executions > 1

  MetricsClient.timing("job.time", event.duration,
                       tags: { job: job_name, queue: queue_name, retry: is_retry },)
end

ActiveSupport::Notifications.subscribe("enqueue_retry.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  job = event.payload.fetch(:job)
  job_name = job.class.name.underscore
  queue_name = job.queue_name
  error = event.payload[:error]
  # Not documented but rails source suggests error can be nil:
  # https://github.com/rails/rails/blob/99096b88ae7a7c9019f2cbcf867e29ba42768e65/activejob/lib/active_job/log_subscriber.rb#L80-L86
  error_name = error.present? ? error.class.name.underscore : "none"

  MetricsClient.increment("job.retry_scheduled",
                          tags: { job: job_name, queue: queue_name, error: error_name },)
end

ActiveSupport::Notifications.subscribe("retry_stopped.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  job = event.payload.fetch(:job)
  job_name = job.class.name.underscore
  queue_name = job.queue_name
  error = event.payload.fetch(:error)
  error_name = error.class.name.underscore

  MetricsClient.increment("job.retry_stopped",
                          tags: { job: job_name, queue: queue_name, error: error_name },)
end

ActiveSupport::Notifications.subscribe("discard.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  job = event.payload.fetch(:job)
  job_name = job.class.name.underscore
  queue_name = job.queue_name
  error = event.payload.fetch(:error)
  error_name = error.class.name.underscore

  MetricsClient.increment("job.discarded",
                          tags: { job: job_name, queue: queue_name, error: error_name },)
end
