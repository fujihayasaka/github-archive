# typed: true
# frozen_string_literal: true

# Generates payload for Security and Analysis webhook events. See Hook::Event::SecurityAndAnalysisEvent
class Hook::Payload::SecurityAndAnalysisPayload < Hook::Payload
  def to_payload_hash
    {
      repository: api_serialize(:full_repository_hash, hook_event.target_repository, show_security_settings: true),
      changes: hook_event.changes
    }
  end
end
