# typed: true
# frozen_string_literal: true

class Hook::Event::SecurityAdvisoryEvent < Hook::Event
  supports_targets Integration

  description "Security advisory published, updated, or withdrawn."

  event_attr :action, :security_advisory_id, required: true

  def security_advisory
    @security_advisory ||= SecurityAdvisory.find(security_advisory_id)
  end

  # These events are not triggered by a user, repository, organization, etc.
  # We do not want to include the "sender" in the webhook payload.
  def actor
    nil
  end
end
