# typed: true
# frozen_string_literal: true

class Hook::Payload::MemberPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      member: api_serialize(:user_hash, hook_event.user),
    }.merge(changes_payload)
  end
end
