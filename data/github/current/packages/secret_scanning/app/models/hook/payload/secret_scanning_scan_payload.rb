# typed: true
# frozen_string_literal: true

# Generates payload for secret scanning alert webhook events. See Hook::Event::SecretScanningScanEvent
class Hook::Payload::SecretScanningScanPayload < Hook::Payload
  def to_payload_hash
    event = T.let(hook_event, Hook::Event::SecretScanningScanEvent)
    hash = {
      action: event.action,
      source: event.source_slug,
      type: event.type_slug,
      started_at: time(event.started_at),
      completed_at: time(event.completed_at),
    }

    hash.merge!({ secret_types: event.secret_types }) if event.pattern_update_backfill?

    hash.merge!({
      custom_pattern_name: event.custom_pattern_name,
      custom_pattern_scope: pattern_scope(event.custom_pattern_scope),
    }) if event.custom_pattern_backfill?

    hash
  end

  def pattern_scope(scope)
    case scope
    when "SCOPE_REPOSITORY"
      "repository"
    when "SCOPE_ORGANIZATION"
      "organization"
    when "SCOPE_ENTERPRISE"
      "enterprise"
    else
      "unknown"
    end
  end

  def time(t)
    ti = Time.at(t["seconds"])
    ti.utc.xmlschema
  end
end
