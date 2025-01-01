# typed: true
# frozen_string_literal: true

class Hook::Payload::DeploymentStatusPayload < Hook::Payload

  delegate :id, :state, :deployment, :environment_url, :log_url, :description, to: :deployment_status

  def to_payload_hash
    {
      deployment_status: api_serialize(:deployment_status_hash, deployment_status),
      deployment: api_serialize(:deployment_hash, deployment),
      check_run: api_serialize(:simple_check_run_hash, hook_event.check_run),
      workflow: api_serialize(:workflow_hash, hook_event.workflow),
      workflow_run: api_serialize(:simple_workflow_run_hash, hook_event.workflow_run),
      action: hook_event.action
    }
  end

  def deployment_status
    hook_event.deployment_status
  end

end
