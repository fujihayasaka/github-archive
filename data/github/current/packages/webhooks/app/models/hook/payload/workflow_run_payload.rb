# typed: true
# frozen_string_literal: true

class Hook::Payload::WorkflowRunPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      workflow_run: api_serialize(:workflow_run_hash, hook_event.workflow_run),
      workflow: api_serialize(:workflow_hash, hook_event.workflow),
    }
  end
end
