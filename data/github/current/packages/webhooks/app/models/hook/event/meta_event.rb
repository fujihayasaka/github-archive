# typed: true
# frozen_string_literal: true

class Hook::Event::MetaEvent < Hook::Event
  supports_targets Marketplace::Listing, Business, *DEFAULT_TARGETS

  description "This particular hook is deleted."

  event_attr :hook_id, :action, :actor_id, required: true

  def hook
    return @hook if defined?(@hook)

    @hook = Hook.find_by(id: hook_id)
  end

  # Override Hook::Event#subscribed_hooks so that this
  # is only delivered to this specific hook.
  def subscribed_hooks
    hooks = []

    if hook
      hooks << hook if hook.events.include?("meta")
      hooks << hook if hook.events.include?("*")
    end

    hooks
  end

  def target_repository
    hook.installation_target if hook&.installation_target.is_a?(Repository)
  end

  def target_organization
    hook.installation_target if hook&.installation_target.is_a?(Organization)
  end

  def target_business
    hook.installation_target if hook&.installation_target.is_a?(Business)
  end

  def actor
    @actor ||= User.find_by(id: actor_id)
  end
end
