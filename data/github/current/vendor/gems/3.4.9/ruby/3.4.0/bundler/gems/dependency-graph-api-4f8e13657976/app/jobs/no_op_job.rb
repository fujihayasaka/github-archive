# frozen_string_literal: true

# A test job used to manually verify health and specific operational characteristics.
class NoOpJob < ApplicationJob
  # Currently, job_params is:
  #   raise_error: true|false
  #   message_to_log: "some message"
  #   sleep_seconds: 10
  def perform(job_params)
    if job_params.has_key?("message_to_log")
      DependencyGraph.logger.info(job_params["message_to_log"])
    end

    if job_params.has_key?("sleep_seconds")
      sleep job_params["sleep_seconds"]
    end

    if job_params.has_key?("raise_error") && job_params["raise_error"]
      raise ArgumentError, "Payload instructed to raise an error!"
    end
  end

  rescue_from(StandardError) do |exception|
    Failbot.report(exception,
      "gh.aqueduct.queue.name" => queue_name,
      "gh.aqueduct.job.name" => "no_op_job"
    )
  end
end
