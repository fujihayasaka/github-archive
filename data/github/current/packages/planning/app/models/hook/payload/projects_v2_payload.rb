# typed: true
# frozen_string_literal: true

class Hook::Payload::ProjectsV2Payload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      projects_v2: api_serialize(:projects_v2_hash, hook_event.project),
      changes: hook_event.changes
    }.compact
  end
end
