# frozen_string_literal: true

# This module handles broken repository detection logic
module BrokenRepoDetection
  extend ActiveSupport::Concern

  JOBS_TO_CHECK_FOR_FAILURES = 15

  private

  def broken_state(update_config)
    return :not_enough_runs if update_config.update_jobs.count < JOBS_TO_CHECK_FOR_FAILURES
    return :broken if most_recent_job(update_config).in_state?(:no_successful_runs)

    :not_broken
  end

  def broken?(update_config)
    case broken_state(update_config)
    when :not_enough_runs
      false
    when :broken
      true
    when :not_broken
      # in the last 15 runs are there any that created pull requests or were processed successfully?
      update_jobs = update_config.update_jobs.
                    where(pull_request_transition_id: nil).
                    order(id: :desc).
                    limit(JOBS_TO_CHECK_FOR_FAILURES)

      no_recent_prs(update_jobs) && no_processed_jobs(update_jobs) && no_pr_limit_errors(update_jobs)
    end
  end

  def no_recent_prs(update_jobs)
    PullRequest.where(update_job_id: update_jobs.pluck(:id)).none?
  end

  def no_processed_jobs(update_jobs)
    UpdateJobTransition.where(update_job_id: update_jobs.pluck(:id)).none? do |transition|
      transition.to_state == "processed"
    end
  end

  def no_pr_limit_errors(update_jobs)
    UpdateJobError.where(
      update_job_id: update_jobs.pluck(:id),
      error_type: "open_pull_request_limit_exceeded"
    ).none?
  end

  def most_recent_job(update_config)
    @most_recent_job ||= update_config.update_jobs.
                         where(pull_request_transition_id: nil).
                         order(id: :desc).first
  end

  def mark_config_broken(update_config, enqueue_scheduled_update_id)
    return unless broken_state(update_config) == :not_broken

    last_job = most_recent_job(update_config)
    last_job_error = last_job&.update_job_errors&.first

    # create a new job in the :no_successful_runs state to signal the update is paused
    job = UpdateJob.create!(
      update_config_id: update_config.id,
      trigger_type: "schedule",
      enqueue_scheduled_update_id: enqueue_scheduled_update_id,
    )
    unless last_job_error.nil?
      # create a copy of the update job error so we can display it in the UI
      UpdateJobError.create!(
        update_job: job,
        error_type: last_job_error.error_type,
        error_details: last_job_error.error_details
      )
    end
    job.transition_to!(:no_successful_runs)
  end
end
