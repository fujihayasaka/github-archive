# typed: true
# frozen_string_literal: true

class Hook::Payload::LabelPayload < Hook::Payload
  def to_payload_hash
    {}.tap do |hash|
      hash[:action]   = hook_event.action
      hash[:label]    = api_serialize(:label_hash, hook_event.label)
      hash[:changes]  = hook_event.changes if hook_event.changes
    end
  end
end
