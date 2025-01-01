# typed: true
# frozen_string_literal: true

class Hook::Payload::MilestonePayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      milestone: api_serialize(:milestone_hash, hook_event.milestone),
    }.merge(changes_payload)
  end
end
