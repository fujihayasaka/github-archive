# typed: true
# frozen_string_literal: true

class Hook::Payload::RepositoryImportPayload < Hook::Payload
  def to_payload_hash
    {
      status: hook_event.status,
    }
  end
end
