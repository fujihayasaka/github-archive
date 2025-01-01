# typed: true
# frozen_string_literal: true

# Generates payload for secret scanning alert webhook events. See Hook::Event::SecretScanningAlertEvent
class Hook::Payload::SecretScanningAlertPayload < Hook::Payload
  def to_payload_hash
    event = T.let(hook_event, Hook::Event::SecretScanningAlertEvent)
    {
      action: event.action,
      alert: api_serialize(:secret_scanning_alert_webhook_hash, event)
    }
  end
end
