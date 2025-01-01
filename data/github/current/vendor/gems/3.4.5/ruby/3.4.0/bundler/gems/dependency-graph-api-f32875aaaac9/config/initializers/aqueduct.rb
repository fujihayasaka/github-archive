# frozen_string_literal: true

# This is inspired by https://github.com/github/meuse/blob/main/config/initializers/aqueduct.rb
Aqueduct.configure do |config|
  config.app = DependencyGraph.aqueduct.app_name

  if Rails.env.development? || Rails.env.test?
    # In a k8s environment, aqueduct-client-ruby will set Aqueduct.site to ENV["KUBE_SITE"]
    # In a local env, ENV["KUBE_SITE"] does not exist, so we set the site to localhost
    config.site = "localhost"

    config.client_id = "dg-api-local-#{Rails.env}"
    config.hostname = "dg-api-local-#{Rails.env}"
  end
end

Aqueduct::Worker.configure do |config|
  config.fork_per_job = false
  config.graceful_term = true

  config.handler = DependencyGraph.aqueduct.method(:work_job)
  config.heartbeat_interval_seconds = DependencyGraph.aqueduct.heartbeat_interval_seconds
  config.heartbeat_check_interval_seconds = DependencyGraph.aqueduct.heartbeat_check_interval_seconds


  config.error_reporter = lambda do |error, job|
    error_class = error.class.name.demodulize.underscore
    context = {}

    if job
      job_class = JSON.parse(job.payload)["job_class"]
      context.merge!({
        "gh.aqueduct.queue.name" => job.queue,
        "gh.aqueduct.job.name" => job_class,
      })
      Instrument.increment("aqueduct.job_error", job: job_class, error: error_class)

      DependencyGraph.logger.with_named_tags(context.merge("gh.dependency_graph.job.payload" => job.payload)) do
        DependencyGraph.logger.error("Error processing job", error)
      end

    else
      Instrument.increment("aqueduct.job_receive_error", error: error_class)
    end

    Failbot.report(error, context)

    # Is this necessary?
    OpenTelemetry.tracer_provider.force_flush
  end

  config.before_perform do |worker, job|
    job_class = JSON.parse(job.payload)["job_class"]
    Instrument.increment("aqueduct.job_begin", job: job_class)
    # Reset the Failbot context before each job run.
    Failbot.reset_context
    Failbot.push worker: worker.to_s
  end

  config.after_perform do
    # Is this necessary?
    OpenTelemetry.tracer_provider.force_flush
    Failbot.reset_context
  end
end
