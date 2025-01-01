# typed: true
# frozen_string_literal: true

class Hook::Payload::ProjectsV2StatusUpdatePayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      projects_v2_status_update: api_serialize(:projects_v2_status_update_hash, hook_event.project_status),
      changes: hook_event.changes
    }.compact
  end
end
