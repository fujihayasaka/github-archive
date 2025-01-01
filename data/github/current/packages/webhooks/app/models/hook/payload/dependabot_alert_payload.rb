# typed: true
# frozen_string_literal: true

class Hook::Payload::DependabotAlertPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      alert: api_serialize(:dependabot_alert_hash, hook_event.alert),
    }
  end
end
