# typed: true
# frozen_string_literal: true

class Hook::Payload::StarPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      starred_at: Api::Serializer.time(hook_event.star&.created_at),
    }
  end
end
