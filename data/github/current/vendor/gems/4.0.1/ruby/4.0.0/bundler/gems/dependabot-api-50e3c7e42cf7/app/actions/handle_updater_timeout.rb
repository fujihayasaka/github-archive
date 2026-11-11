# frozen_string_literal: true

# Processes timeout outcomes returned from the Dependabot Updater
class HandleUpdaterTimeout
  attr_reader :update_job, :event_source

  delegate :update_config, to: :update_job

  def initialize(update_job:, event_source:)
    @update_job = update_job
    @event_source = event_source
  end

  def run
    Dependabot::Exceptions.push(update_job.telemetry_attributes)

    if job_never_started?
      handle_job_never_started
      handle_job_never_started_errors
    else
      handle_job_timed_out
      handle_job_timed_out_errors
    end

    cancel_pull_request_updates

    update_job.increment_metric("updater_timeout.handled")

    true
  rescue Statesman::TransitionFailedError
    # If a transition fails, it can mean the UpdateJob was marked as
    # complete while this job was running, in which case we should
    # treat it as a noop.
    update_job.completed? ? return : raise
  end

  private

  # Check if the job was never picked up by a runner (still pending or enqueued)
  def job_never_started?
    update_job.current_state.in?(%w(pending enqueued))
  end

  # Job was never picked up by a runner - transition to abandoned
  def handle_job_never_started
    # If pending, first transition to enqueued so we can reach abandoned
    update_job.transition_to!(:enqueued) if update_job.current_state == "pending"

    Statesman::Machine.retry_conflicts do
      update_job.transition_to!(:abandoned)
    end

    update_job.increment_metric(
      "mark_as_processed.abandoned",
      tags: {
        config_file: update_job.update_config.using_config_file?,
        event_source: event_source,
        reason: "job_never_started",
      }
    )
  end

  def handle_job_never_started_errors
    error_type = if update_job.self_hosted?
                   "self_hosted_runner_unavailable"
                 else
                   "actions_service_unavailable"
                 end

    update_job.update_job_errors.create!(error_type: error_type) if update_job.unique_errors.none?
    NotifyGitHubOfFailureJob.send_errors_for(update_job)
  end

  def handle_job_timed_out
    Statesman::Machine.retry_conflicts do
      update_job.transition_to!(:timed_out)
    end

    update_job.increment_metric(
      "mark_as_processed.timed_out",
      tags: {
        config_file: update_job.update_config.using_config_file?,
        event_source: event_source,
      }
    )
  end

  def handle_job_timed_out_errors
    update_job.update_job_errors.create!(error_type: "timed_out") if update_job.unique_errors.none?
    NotifyGitHubOfFailureJob.send_errors_for(update_job)
  end

  # If the job was created to update an existing PR, we need to dispatch
  # a CancelStalePullRequestUpdate job, otherwise do nothing.
  def cancel_pull_request_updates
    return unless update_job.pull_request_transition&.most_recent?

    CancelStalePullRequestUpdate.
      set(wait: 10.minutes).
      perform_later(update_job: update_job)
  end
end
