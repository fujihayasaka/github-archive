# typed: true
# frozen_string_literal: true

class Hook::Payload::ProjectsV2ItemPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      projects_v2_item: api_serialize(:projects_v2_item_hash, hook_event.item),
      changes: hook_event.changes,
    }.compact
  end
end
