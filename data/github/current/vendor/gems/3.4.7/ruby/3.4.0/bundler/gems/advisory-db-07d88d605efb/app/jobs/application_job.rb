# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  include HasCurrentUser

  retry_on AdvisoryDB::Lock::AlreadyLocked, queue: :high, wait: :polynomially_longer

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # FYI:this implicitly avoids anything configured with discard_on .
  around_perform do |_job, block|
    block.call
  rescue StandardError => error
    payload = {
      job_name: self.class.to_s,
    }

    # We *could* do this, but currently Resque::Failure::Failbot logs this on final failure, configured in config/initializers/resque.rb
    # Failbot.report!(error, payload)
    ::GitHub::Telemetry::Logs.logger.error(
      "Job failed and may be retried",
      {
        exception: error,
        "gh.job.name": payload[:job_name],
      },
    )
    raise
  end

  # Override this in your job if you'd like to include custom tags
  def stats_tags
    []
  end

  def all_stats_tags(error: $ERROR_INFO, attempt_number: 0)
    [
      "class:#{self.class.name.underscore}",
      "queue:#{queue_name}",
      "adapter:#{self.class.queue_adapter_name}",
      error ? "error:#{error.class.to_s.underscore}" : nil, # to_s accounts for anonymous classes
      ("attempt_number:#{attempt_number}" if attempt_number > 0),
    ].concat(stats_tags).compact
  end
end
