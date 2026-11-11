# frozen_string_literal: true

Aqueduct::Rails.configure do |config| # rubocop:disable Metrics/BlockLength
  # Required: The name of the app to use for sending and receiving jobs in Aqueduct.
  # For example, "<app-name>-#{Rails.env}"
  config.app = "dependabot-api"
  config.url = Prius.get(:aqueduct_url)

  # Optional: Which logger to use, defaults to Rails.logger
  # config.logger = Rails.logger

  # Optional: Which aqueduct client to use, defaults to a standard client
  # config.aqueduct_client = Aqueduct::Client.new

  config.api_key = Prius.get(:aqueduct_api_key)
  config.api_key_version = Prius.get(:aqueduct_api_key_version)&.to_i

  # Optional: How often to heartbeat in workers, defaults to 60 seconds
  # config.heartbeat_interval_seconds = 60

  # Optional: How long should Aqueduct wait before assuming the worker has
  # crashed and the job should be redelivered, defaults to 10 minutes.
  # config.redelivery_timeout_seconds = 10.minutes

  # Optional: How many redelivery attempts should Aqueduct make (not including
  # the initial delivery) if the worker crashes, defaults to 2
  # config.max_redelivery_attempts = 2

  # Optional: A proc that will be called with the error and job (if applicable)
  # when an error is encountered. Defaults to printing the error and backtrace
  # to STDERR
  # config.error_reporter = ->(error, job = nil) { Failbot.report(error) }

  config.error_reporter = lambda do |error, job = nil|
    # These errors occur during aqueduct's handling of jobs and not during the
    # execution of the job itself. We don't want to report them to failbot unless
    # they can be identified as a critical error we need to handle ourselves. The
    # current errors are primarily network errors that we can't do anything about
    # and will be retried automatically.
    #
    # Errors that occur during the execution of a job are reported to failbot in
    # app/job/application_job.rb

    error_name = error.class.name.underscore

    if job
      job_class = JSON.parse(job.payload)["serialized_active_job"]["job_class"]
      job_name = job_class.to_s.underscore

      MetricsClient.increment("aqueduct.rails.error", tags: { job: job_name, error: error_name })
      Dependabot::Logger.error(
        msg: "Aqueduct::Rails error reported",
        "code.namespace": job_class,
        "exception.type": error.class,
        "exception.message": error.message,
        "exception.stacktrace": error.backtrace,
      )
    else
      MetricsClient.increment("aqueduct.rails.error", tags: { job: "none", error: error_name })
      Dependabot::Logger.error(
        msg: "Aqueduct::Rails error reported",
        "code.namespace": "none",
        "exception.type": error.class,
        "exception.message": error.message,
        "exception.stacktrace": error.backtrace,
      )
    end
  end
end

Aqueduct::Rails::Metrics::Subscriber.subscribe(reporter: MetricsClient)

Aqueduct::Worker.configure do |config|
  config.worker_pool = "dependabot-api-#{ENV.fetch('GH_OTEL_K8S_CONTAINER_NAME', 'unknown')}"
end
