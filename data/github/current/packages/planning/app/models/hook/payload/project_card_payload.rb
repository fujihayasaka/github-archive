# typed: true
# frozen_string_literal: true

class Hook::Payload::ProjectCardPayload < Hook::Payload
  def to_payload_hash
    {}.tap do |payload|
      payload[:action]  = hook_event.action
      payload[:changes] = hook_event.changes if hook_event.changes
      if hook_event.action.to_sym == :moved
        payload[:project_card] = api_serialize(:project_card_hash, hook_event.project_card, { after_id: hook_event.after_id })
      else
        payload[:project_card] = api_serialize(:project_card_hash, hook_event.project_card)
      end
    end
  end
end
