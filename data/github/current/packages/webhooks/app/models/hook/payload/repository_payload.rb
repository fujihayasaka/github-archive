# typed: true
# frozen_string_literal: true

class Hook::Payload::RepositoryPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
    }.merge(changes_payload)
  end
end
