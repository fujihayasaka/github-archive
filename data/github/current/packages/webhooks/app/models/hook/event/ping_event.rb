# typed: true
# frozen_string_literal: true

class Hook::Event::PingEvent < Hook::Event
  supports_targets Marketplace::Listing, Business, *DEFAULT_TARGETS
  auto_subscribed

  description "Hook created."

  event_attr :hook_id, required: true

  def hook
    @hook ||= Hook.find(hook_id)
  end

  # Override Hook::Event#subscribed_hooks so that this
  # is only delivered to this specifig hook.
  def subscribed_hooks
    [hook]
  end

  def target_repository
    hook.installation_target if hook.installation_target.is_a?(Repository)
  end

  def target_organization
    hook.installation_target if hook.installation_target.is_a?(Organization)
  end

  def target_business
    hook.installation_target if hook.installation_target.is_a?(Business)
  end

  def actor
    hook.creator
  end
end
