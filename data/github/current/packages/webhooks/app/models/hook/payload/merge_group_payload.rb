# typed: true
# frozen_string_literal: true

class Hook::Payload::MergeGroupPayload < Hook::Payload

  def to_payload_hash
    base_payload = {
      action: hook_event.action,
      merge_group: api_serialize(:merge_group_hash, hook_event.entry, hook: true),
    }

    if hook_event.action.to_s == "destroyed"
      base_payload.merge(
        reason: hook_event.destroyed_reason,
      )
    else
      base_payload
    end
  end
end
