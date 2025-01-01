# typed: true
# frozen_string_literal: true

class Hook::Payload::WatchPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
    }
  end

end
