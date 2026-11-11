# typed: true
# frozen_string_literal: true

class Hook::Payload::RepositoryAdvisoryPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      repository_advisory: api_serialize(:repository_advisory_hash, hook_event.repository_advisory),
    }
  end
end
