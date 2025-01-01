# typed: true
# frozen_string_literal: true

class Hook::Payload::ProjectPayload < Hook::Payload
  def to_payload_hash
    {}.tap do |payload|
      payload[:action]  = hook_event.action
      payload[:project] = api_serialize(:project_hash, hook_event.project)
      payload[:changes] = hook_event.changes if hook_event.changes
    end
  end
end
