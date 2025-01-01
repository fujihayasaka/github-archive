# typed: true
# frozen_string_literal: true

# Generates payload for secret scanning alert webhook events. See Hook::Event::SecretScanningAlertLocationEvent
class Hook::Payload::SecretScanningAlertLocationPayload < Hook::Payload
  def to_payload_hash
    event = T.let(hook_event, Hook::Event::SecretScanningAlertLocationEvent)
    {
      action: event.action,
      location: api_serialize(:secret_scanning_alert_location_webhook_hash, event),
      alert: api_serialize(:secret_scanning_alert_webhook_hash, event),
    }
  end
end
