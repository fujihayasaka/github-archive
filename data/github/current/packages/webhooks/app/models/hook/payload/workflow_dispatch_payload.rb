# typed: true
# frozen_string_literal: true

class Hook::Payload::WorkflowDispatchPayload < Hook::Payload
  def to_payload_hash
    {
      ref: hook_event&.ref,
      workflow: hook_event&.workflow,
      inputs: hook_event&.inputs,
    }
  end
end
