# typed: false
# frozen_string_literal: true

class Hook::Event::DeploymentReviewEvent < Hook::Event

  supports_targets Integration
  description "Deployment review requested, approved or rejected"

  event_attr :action, required: true
  event_attr :gate_approval_id, :gate_approval_log_id, :deployment_status_id, :comment, required: false

  def deliverable?
    target_repository&.present? && deployment_status&.present? && reviewers.any?
  end

  def deployment_status
    if deployment_status_id.present?
      @deployment_status ||= DeploymentStatus.includes(deployment: { check_run: [:check_suite] }).find_by_id(deployment_status_id)
    else
      @deployment_status ||= gate_requests[0].check_run.deployment.latest_status
    end
    @deployment_status
  end

  def deployment
    deployment_status&.deployment
  end

  def check_run
    deployment.check_run
  end

  def check_suite
    check_run.check_suite
  end

  def gate_requests
    if deployment_status_id.present?
      @gate_requests ||= GateRequest.includes(gate: :environment).where(check_run_id: check_run.id)
    elsif gate_approval_log_id.present?
      @gate_approvals ||= GateApproval.includes(:gate_approval_log).where(gate_approval_log: { id: gate_approval_log_id })
      @gate_requests ||= GateRequest.includes(:gate_approvals).where(gate_approvals: { gate_request_id: @gate_approvals.filter_map { |a| a.gate_request_id } })
    else
      raise ArgumentError.new("deployment_status_id or gate_approval_log_id is required")
    end
    @gate_requests
  end

  def environment
    deployment&.environment
  end

  def workflow_run
    check_suite.workflow_run
  end

  def workflow_job_run
    check_run.workflow_job_run
  end

  def reviewers
    @reviewers ||= GateApprover.where(gate_id: gate_requests.filter_map { |gr| gr.gate&.id })
  end

  def target_repository
    deployment_status&.repository
  end

  def actor
    deployment_status&.creator
  end

  def approver
    GateApprovalLog.find(gate_approval_log_id).user if gate_approval_log_id.present?
  end
end
