# typed: true
# frozen_string_literal: true
class Hook::Payload::OrgBlockPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      blocked_user: api_serialize(:user_hash, hook_event.blocked_user),
    }
  end
end
