# typed: true
# frozen_string_literal: true

class Hook::Event::GitHubAppAuthorizationEvent < Hook::Event
  supports_targets Integration
  auto_subscribed
  description "GitHub App user authorization is revoked."

  event_attr :action, :actor_id, :integration_id, required: true

  # In the event we couldn't find the actor due to
  # deletion of the User.
  def deliverable?
    actor.present? && integration.present?
  end

  def subscribed_hooks
    return [] unless integration&.active_and_subscribable?

    [integration.hook]
  end

  def actor
    return @actor if defined?(@actor)
    @actor = User.find_by(id: actor_id)
  end

  def integration
    return @integration if defined?(@integration)
    @integration = Integration.find_by(id: integration_id)
  end
end
