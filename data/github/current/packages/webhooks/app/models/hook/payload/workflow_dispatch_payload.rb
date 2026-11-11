# typed: true
# frozen_string_literal: true

class Hook::Payload::WorkflowDispatchPayload < Hook::Payload
  def to_payload_hash
    payload = {
      ref: hook_event&.ref,
      workflow: hook_event&.workflow,
      inputs: hook_event&.inputs,
    }

    # Include actions_meta if present
    if hook_event&.actions_meta.present?
      payload[:actions_meta] = hook_event.actions_meta
    end

    payload
  end
end
