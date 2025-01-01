# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("enqueue.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  job = event.payload.fetch(:job)
  job_name = job.class.name.underscore
  queue_name = job.queue_name
  depth = Resque.size(queue_name)

  AdvisoryDB.stats.increment("job.enqueued", {
    tags: AdvisoryDB.dogtags(job: job_name, queue: queue_name),
  })

  AdvisoryDB.stats.gauge("job.depth", depth, {
    tags: AdvisoryDB.dogtags(queue: queue_name),
  })
end

ActiveSupport::Notifications.subscribe("enqueue_at.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  job = event.payload.fetch(:job)
  job_name = job.class.name.underscore
  queue_name = job.queue_name
  depth = Resque.size(queue_name)

  AdvisoryDB.stats.increment("job.scheduled", {
    tags: AdvisoryDB.dogtags(job: job_name, queue: queue_name),
  })

  AdvisoryDB.stats.gauge("job.depth", depth, {
    tags: AdvisoryDB.dogtags(queue: queue_name),
  })
end

ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  job, error = event.payload.values_at(:job, :exception_object)
  tags = job.all_stats_tags(error: error)
  depth = Resque.size(job.queue_name)

  # historical events
  AdvisoryDB.stats.timing("job.time", event.duration, { tags: tags })
  AdvisoryDB.stats.gauge("job.depth", depth, { tags: tags })
  # events aligning with github (see https://github.com/github/github/blob/feb7eb58802e72a74a30231340e5e7baf7505796/config/instrumentation/jobs.rb#L208)
  AdvisoryDB.stats.increment("active_job.performed", tags: tags)
  AdvisoryDB.stats.distribution("active_job.perform.dist.time", event.duration, tags: tags)
end

ActiveSupport::Notifications.subscribe("error.active_job") do |*, payload|
  if payload[:on] == :enqueue
    payload.values_at(:job, :error).tap do |job, error|
      AdvisoryDB.stats.increment("active_job.enqueue_error", tags: job.all_stats_tags(error: error))
    end
  end

  payload.values_at(:job, :error, :on).tap do |job, error, on|
    tags = job.all_stats_tags(error: error)
    tags << "on:#{on}" if on
    AdvisoryDB.stats.increment("active_job.error", tags: tags)
  end
end

ActiveSupport::Notifications.subscribe("enqueue_retry.active_job") do |*, payload|
  payload.values_at(:job, :error, :wait).tap do |job, error, wait|
    if error
      GitHub::Telemetry::Logs.logger.error(
        "Retrying #{job.class} in #{wait} seconds, due to a #{error.class}. The original exception was #{error.cause.inspect}.",
        {
          exception: error,
          "code.namespace": job.class.name,
          "gh.job.attempts": job.executions,
        },
      )
      AdvisoryDB.stats.increment("active_job.retry", tags: job.all_stats_tags(error: error, attempt_number: job.executions))
    end
  end
end

ActiveSupport::Notifications.subscribe("retry_stopped.active_job") do |*, payload|
  payload.values_at(:job, :error).tap do |job, error|
    if error
      GitHub::Telemetry::Logs.logger.error("Stopped retrying #{job.class} due to a #{error.class}, which reoccurred on #{job.executions} attempts. The original exception was #{error.cause.inspect}.")
      AdvisoryDB.stats.increment("active_job.stop_retry", tags: job.all_stats_tags(error: error))
    end
  end
end
