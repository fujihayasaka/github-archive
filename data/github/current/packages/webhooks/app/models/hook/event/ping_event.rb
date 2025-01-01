# typed: true
# frozen_string_literal: true

class Hook::Event::PingEvent < Hook::Event
  supports_targets Marketplace::Listing, Business, *DEFAULT_TARGETS
  auto_subscribed

  description "Hook created."

  event_attr :hook_id, required: true

  def hook
    # Use a cached model if available.
    return @_models[:hook] if @_models[:hook]
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
    if hook.installation_target.is_a?(Organization)
      hook.installation_target
    elsif hook.installation_target.is_a?(Repository)
      owner = hook.installation_target.owner
      owner if owner.is_a?(Organization)
    end
  end

  def target_business
    hook.installation_target if hook.installation_target.is_a?(Business)
  end

  def actor
    hook.creator
  end

  private

  sig { returns(Events::Tier1Event) }
  def tier1_event
    Events::Domain::Tier1EventBuilder.new
      .action(:EVENT_ACTION_NONE)
      .event_type(:EVENT_TYPE_PING)
      .guid(guid)
      .primary_entity(hook)
      .repository(target_repository)
      .business(target_business)
      .organization(target_organization)
      .actor(actor)
      .hook_event_attributes(Hydro::Schemas::Github::HookEventAttributes::V0::PingEventAttributes.new({
        hook_id: hook_id,
      }))
      .single_hook_webhooks_delivery_scope(hook_id)
      .build_tier_1_event
  end
end
