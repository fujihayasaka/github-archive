# typed: true
# frozen_string_literal: true

class Hook::Payload::DeploymentPayload < Hook::Payload

  def to_payload_hash
    {
      deployment: api_serialize(:deployment_hash, hook_event.deployment),
      action: hook_event.action,
      workflow: api_serialize(:workflow_hash, hook_event.workflow),
      workflow_run: api_serialize(:simple_workflow_run_hash, hook_event.workflow_run)
    }
  end

end
