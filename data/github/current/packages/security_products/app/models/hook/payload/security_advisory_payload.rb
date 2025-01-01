# typed: true
# frozen_string_literal: true

class Hook::Payload::SecurityAdvisoryPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      security_advisory: api_serialize(:security_advisory_hash, hook_event.security_advisory),
    }
  end
end
