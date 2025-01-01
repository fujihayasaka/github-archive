# typed: true
# frozen_string_literal: true

class Hook::Payload::UserPayload < Hook::Payload
  def to_payload_hash
    {
      user: api_serialize(:user_hash, hook_event.user),
      action: hook_event.action,
    }
  end
end
