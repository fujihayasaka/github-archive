# typed: true
# frozen_string_literal: true

class Hook::Payload::ReleasePayload < Hook::Payload
  def to_payload_hash
    {}.tap do |payload|
      payload[:action]  = hook_event.action
      payload[:changes] = hook_event.changes if hook_event.changes
      payload[:release] = api_serialize(:release_hash, hook_event.release)
    end
  end
end
