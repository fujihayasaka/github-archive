# typed: true
# frozen_string_literal: true

# Generates payload for secret scanning alert webhook events. See Hook::Event::SecretScanningAlertEvent
class Hook::Payload::SecretScanningAlertPayload < Hook::Payload
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_payload_hash
    event = T.let(hook_event, Hook::Event::SecretScanningAlertEvent)
    {
      action: event.action,
      alert: api_serialize(:secret_scanning_alert_webhook_hash, event)
    }.merge(meta_payload)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def meta_payload
    case hook_event.action.to_sym
    when :assigned, :unassigned
      assignee_payload
    else
      {}
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def assignee_payload
    return {} unless hook_event.assignee

    {
      assignee: api_serialize(:user_hash, hook_event.assignee)
    }
  end
end
