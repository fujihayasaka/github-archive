# typed: true
# frozen_string_literal: true

class Hook::Payload::ProjectColumnPayload < Hook::Payload
  def to_payload_hash
    {}.tap do |payload|
      payload[:action]  = hook_event.action
      payload[:changes] = hook_event.changes if hook_event.changes
      if hook_event.action.to_sym == :moved
        payload[:project_column] = api_serialize(:project_column_hash, hook_event.project_column, { after_id: hook_event.after_id })
      else
        payload[:project_column] = api_serialize(:project_column_hash, hook_event.project_column)
      end
    end
  end
end
