# typed: true
# frozen_string_literal: true

class Hook::Payload::DeployKeyPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      key: api_serialize(:public_key_hash, hook_event.key),
    }
  end
end
