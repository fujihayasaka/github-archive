# frozen_string_literal: true

# Processes failure outcomes when attempting to dispatch workloads
# to Actions
#
# This class does not implement retries as it assumes that either:
# - PrioritizedJobs::StartUpdateJob has been used to retry to exhaustion
# - We are handling the failure from a workflow_run webhook and no retry is feasible
class HandleActionsRunnerFailure
  JOB_ERROR_UNKNOWN = "actions_service_unknown"

  JOB_ERRORS_FOR_OCTOKIT = {
    Octokit::InternalServerError => "actions_service_failed",
    Octokit::NotFound => "actions_service_repository_not_found",
    Octokit::ServiceUnavailable => "actions_service_unavailable",
    Octokit::TooManyRequests => "octokit_rate_limited",
    Octokit::Unauthorized => "octokit_unauthorized",
    Octokit::UnprocessableEntity => "actions_service_unprocessable",
  }.freeze

  attr_reader :update_job, :error

  def initialize(update_job:, error: nil)
    @update_job = update_job
    @error = error
  end

  def run
    update_job.ensure_job_is_processing
    add_error_to_update_job

    update_job.transition_to!(
      :processed_with_errors,
      errors: update_job.unique_errors.map(&:error_hash),
    )

    NotifyGitHubOfFailureJob.send_errors_for(update_job)
  end

  private

  def add_error_to_update_job
    return create_update_job_error(JOB_ERROR_UNKNOWN, {}) if error.blank?

    if error.is_a?(Octokit::Error)
      handle_octokit_error
    else
      handle_unknown_error
    end
  end

  def handle_octokit_error
    error_type = JOB_ERRORS_FOR_OCTOKIT.fetch(error.class, JOB_ERROR_UNKNOWN)
    create_update_job_error(error_type, message: error.response_body)

    Dependabot::Logger.error(
      msg: "Octokit raised an error when starting the job in Actions.",
      "code.namespace": self.class.name.to_s,
      "exception.type": error.class,
      "exception.message": error.response_body,
      **update_job.telemetry_attributes,
    )
  end

  def handle_unknown_error
    create_update_job_error("actions_service_unknown", message: error.message)

    Dependabot::Logger.error(
      msg: "There was an unknown error when starting the job in Actions.",
      "code.namespace": self.class.name.to_s,
      "exception.type": error.class,
      "exception.message": error.message,
      **update_job.telemetry_attributes,
    )
  end

  def create_update_job_error(error_type, error_details)
    UpdateJobError.create!(
      update_job: update_job,
      error_type: error_type,
      error_details: error_details,
    )
  end
end
