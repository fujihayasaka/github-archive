# typed: false
# frozen_string_literal: true

class GateApproval < ApplicationRecord::ActionsEnvironments
  include Instrumentation::Model

  enum :state, {
    rejected: 0, # the gate was rejected by a user or github app.
    approved: 1, # the gate was approved by a user or github app.
    skipped: 2,  # the gate was skipped via admin "break glass" functionality.
    canceled: 3, # the gate was not evaluated because the workflow run was canceled or another gate was rejected.
    pending: 4   # the pending custom gate was commented on by a github app.
  }

  belongs_to :gate_request
  belongs_to :environment
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :approver, polymorphic: true
  belongs_to :user
  belongs_to :gate_approval_log

  validate :user_can_approve

  after_commit :instrument_state_changed, on: [:create, :update]

  def user_can_approve
    # Allow any user to reject a gate request when deleting an environment
    return if rejected? && (environment.nil? || environment.destroyed?)
    # Allow any user to reject a gate request when deleting a gate
    return if rejected? && gate_request.reload.gate.nil?
    # Allow any user to skip a gate request if break glass is enabled for the environment
    # Note: We check that the user is an admin before we get here
    return if skipped? && !environment.gates_admin_enforced
    # Allow any user to reject a gate request if they canceled the run or rejected a sibling gate request
    return if canceled?
    # Allow the GitHub Actions app to create approval log entries for timers
    return if approved? && gate_request.gate.timeout? && approver.id == GitHub.launch_github_app.bot.id

    unless gate_request.approval_status(user) == "pending"
      errors.add :user, "does not have a pending approval"
    end
  end

  def workflow_run
    gate_request.check_run.check_suite.workflow_run
  end

  def environment_name
    # environment may be deleted, and in that case we take the name from the deployment
    environment&.name || gate_request.check_run.deployment&.latest_environment
  end

  private

  def instrument_state_changed
    GitHub.instrument(event_name_from_state, event_payload) if repository.can_emit_actions_audit_logs?
  end

  def event_name_from_state
    # Special case for break-glass scenarios
    return "workflows.bypass_protection_rules" if skipped?

    return "workflows.comment_workflow_job" if pending?

    approved? ? "workflows.approve_workflow_job" : "workflows.reject_workflow_job"
  end

  def event_payload
    {
      gate_approval_id: id,
      actor: user,
      repo: repository,
      workflow_run_id: workflow_run.id,
      run_number: workflow_run.run_number,
      env_id: environment.id,
      env_name: environment.name,
      comment: gate_approval_log&.comment
    }.tap do |h|
      h[:org] = repository.owner if repository.owner.organization?
      h[:business] = repository.owner.business if repository.owner.business.present?
      h[:team] = approver if approver.is_a?(Team)
    end
  end
end
