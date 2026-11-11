# frozen_string_literal: true

class UpdateJobStateMachine
  include Statesman::Machine
  include DenormalizeCurrentStateToModel

  state :pending, initial: true
  state :cancelled
  state :enqueued
  state :abandoned
  state :processing
  state :processed
  state :processed_with_errors
  state :timed_out
  state :pending_retry
  state :no_successful_runs

  transition from: :pending,    to: %i(enqueued cancelled no_successful_runs)
  transition from: :enqueued,   to: %i(processing pending abandoned)
  transition from: :processing, to: %i(processed processed_with_errors
                                       timed_out)
  transition from: :processed_with_errors, to: %i(pending_retry)
  transition from: :timed_out, to: %i(pending_retry abandoned)
  transition from: :pending_retry, to: %i(enqueued cancelled)
  transition from: :cancelled, to: %i(pending_retry)

  # All processed_with_errors jobs should have details of the error
  guard_transition(to: :processed_with_errors) do |_, _, metadata|
    metadata[:errors].present?
  end

  guard_transition(to: :abandoned, from: :timed_out) do |update_job, _, _|
    update_job.self_hosted?
  end

  before_transition(to: :enqueued) do |update_job, transition|
    update_job.hashed_token = transition.metadata.delete("hashed_token")
    update_job.hashed_credentials_token =
      transition.metadata.delete("hashed_credentials_token")
    update_job.save!
  end

  before_transition(from: :enqueued, to: :pending) do |update_job, _|
    update_job.update!(hashed_token: nil, hashed_credentials_token: nil)
    CancelActionsWorkflowRunJob.perform_later(update_job, update_job.actions_workflow_run_id)
  end

  before_transition(from: :enqueued, to: :abandoned) do |update_job, _|
    update_job.update!(hashed_token: nil, hashed_credentials_token: nil)
    CancelActionsWorkflowRunJob.perform_later(update_job, update_job.actions_workflow_run_id)
  end

  before_transition(to: :processing) do |update_job, _|
    expires_at = Time.now.in_time_zone + update_job.max_run_time
    update_job.update!(expires_at: expires_at)
  end

  before_transition(to: :pending_retry) do |update_job, _|
    update_job.update!(hashed_token: nil, hashed_credentials_token: nil)
  end

  # rubocop:disable Metrics/BlockLength
  after_transition(after_commit: true) do |update_job, transition|
    transitions = update_job.history.to_a
    if transitions.count > 1
      duration = transition.created_at - transitions[-2].created_at
      from_state = transitions[-2].to_state
    else
      duration = transition.created_at - update_job.created_at
      from_state = "pending"
    end

    update_job.increment_metric("update_job.transitioned",
                                tags: {
                                  from_state: from_state,
                                  to_state: transition.to_state,
                                })

    update_job.timing_metric("update_job.transition.time",
                             duration,
                             tags: {
                               from_state: from_state,
                               to_state: transition.to_state,
                             })

    Dependabot::Logger.info(
      msg: "UpdateJob state changed.",
      "code.namespace": "UpdateJobStateMachine",
      "gh.dependabot_api.update_job.created_at": update_job.created_at,
      "gh.dependabot_api.update_job.trigger_type": update_job.trigger_type,
      "gh.dependabot_api.update_job.from_state": from_state,
      "gh.dependabot_api.update_job.to_state": transition.to_state,
      **update_job.telemetry_attributes,
    )

    # Log additional context for potential silent failures in group updates
    log_group_transition_context(update_job, from_state, transition.to_state)
  end
  # rubocop:enable Metrics/BlockLength

  def self.log_group_transition_context(update_job, from_state, to_state)
    # Enhanced logging for group update lifecycle events that could indicate silent failures
    return unless update_job.dependency_groups.any?

    log_event_for_state(update_job, from_state, to_state)
  end

  def self.log_event_for_state(update_job, from_state, to_state)
    level, message, extra_params = case to_state
                                   when "abandoned"
                                     [:warn, "Group update job abandoned - potential silent failure",
                                      { potential_silent_failure: true },]
                                   when "timed_out"
                                     [:warn, "Group update job timed out - potential silent failure",
                                      { potential_silent_failure: true },]
                                   when "processed_with_errors"
                                     error_details = update_job.update_job_errors.map(&:error_type)
                                     [:warn, "Group update job completed with errors",
                                      { error_types: error_details, error_count: error_details.count },]
                                   when "processed"
                                     [:info, "Group update job completed successfully", {}]
                                   else
                                     return
                                   end

    # Emit specific group update state transition metrics for important states
    emit_group_state_metrics(update_job, from_state, to_state, extra_params)

    log_group_update_event(update_job, from_state, to_state, level, msg: message, **extra_params)
  end

  def self.emit_group_state_metrics(update_job, from_state, to_state, extra_params)
    case to_state
    when "abandoned", "timed_out"
      emit_silent_failure_metric(update_job, from_state, to_state)
    when "processed_with_errors"
      emit_error_completion_metric(update_job, extra_params)
    when "processed"
      emit_successful_completion_metrics(update_job)
    end
  end

  def self.emit_silent_failure_metric(update_job, from_state, to_state)
    # These are potential silent failures - track them specifically
    update_job.increment_metric("grouped_update.silent_failure",
                                tags: {
                                  reason: to_state,
                                  from_state: from_state,
                                })
  end

  def self.emit_error_completion_metric(update_job, extra_params)
    # Track error scenarios with error context
    error_types = extra_params[:error_types] || []
    primary_error = error_types.first || "unknown"

    update_job.increment_metric("grouped_update.completed_with_errors",
                                tags: {
                                  primary_error_type: primary_error,
                                  error_count: error_types.count,
                                })
  end

  def self.emit_successful_completion_metrics(update_job)
    # Track successful group completions
    update_job.increment_metric("grouped_update.completed_successfully")

    # Detect silent failures: job completed successfully but created no PRs
    return unless update_job.groups? && !pending_prs?(update_job)

    reason = determine_no_pr_reason(update_job)
    update_job.increment_metric("grouped_update.no_pr_created",
                                tags: {
                                  reason: reason,
                                  silent_failure: true,
                                })
  end

  def self.log_group_update_event(update_job, from_state, to_state, level, **)
    context = {
      "code.namespace": "UpdateJobStateMachine",
      "gh.dependabot_api.update_job.from_state": from_state,
      "gh.dependabot_api.update_job.to_state": to_state,
      **update_job.telemetry_attributes,
    }

    Dependabot::Logger.public_send(level, **context, **)
  end

  # Helper method to check if an update job has created any pending PRs
  def self.pending_prs?(update_job)
    PendingPullRequest.exists?(update_job_id: update_job.id)
  end

  # Helper method to determine why no PR was created
  def self.determine_no_pr_reason(update_job)
    # Check for common reasons why no PR might be created
    if update_job.update_job_errors.exists?
      "dependency_resolution_failed"
    elsif update_job.dependencies.blank?
      "no_dependencies_specified"
    elsif existing_pr_for_dependencies?(update_job)
      "existing_pr_found"
    else
      "no_updates_available"
    end
  end

  # Helper method to check if there's already a PR for the same dependencies
  def self.existing_pr_for_dependencies?(update_job)
    return false if update_job.dependencies.blank?

    # Look for existing open PRs in the same update config that might conflict
    update_job.update_config.pull_requests.open.exists?
  end

  private_class_method :log_group_transition_context, :log_group_update_event, :log_event_for_state,
                       :emit_group_state_metrics, :pending_prs?, :determine_no_pr_reason,
                       :existing_pr_for_dependencies?
end
