# typed: true
# frozen_string_literal: true

class Hook::Payload::DeploymentReviewPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      workflow_run: api_serialize(:workflow_run_hash, hook_event.workflow_run),
      since: Api::Serializer.time(hook_event.triggered_at),
    }.merge(meta_payload)
  end

  def meta_payload
    case hook_event.action.to_sym
    when :requested
      requested_payload
    when :approved, :rejected
      approval_rejection_payload
    else
      {}
    end
  end

  def requested_payload
    {
      workflow_job_run: api_serialize(:simple_workflow_job_run_hash, hook_event.workflow_job_run),
      environment: hook_event.environment,
      reviewers: hook_event.reviewers.map do |reviewer|
        api_serialize(:gate_reviewer_hash, reviewer)
      end,
      requestor:  api_serialize(:simple_user_hash, hook_event.actor)
    }
  end

  def approval_rejection_payload
    {
      workflow_job_runs: api_serialize(:simple_workflow_job_runs_hash, hook_event.gate_requests.map { |g| g.check_run.workflow_job_run }),
      approver: api_serialize(:simple_user_hash, hook_event.approver),
      comment: hook_event.comment
    }
  end

end
