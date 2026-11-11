# typed: true
# frozen_string_literal: true

class OauthAuthorization::AbilityCollection < Ability::Collection
  # Internal: Used by Abilities to ensure that only OauthAuthorizations
  # can be granted abilities on a Collection
  def grant?(actor, action)
    actor.can_have_granular_user_permissions?
  end

  # Public: access control on the collection
  #
  # actor: - The User to check permission for.
  # action - The Symbol action representing the level of permission to check for.
  #
  # Returns true or false.
  def permit?(actor, action)
    async_permit?(actor, action).sync
  end

  def async_permit?(actor, action)
    resolved_actor = resolve_actor(actor).sync

    if resolved_actor.is_a?(OauthAccess) &&
        ::Apps::Privileged.capable?(:user_permissions_always_uses_latest_version, app: resolved_actor.application)
      application_has_permission?(oauth_access: resolved_actor, action: action)
    else
      async_has_direct_permission?(actor: resolved_actor, action: action).then do |result|
        result || async_has_granular_user_permission?(actor: resolved_actor, action: action)
      end
    end
  end

  private

  # If the actor has a hydrated OauthAccess or UserProgrammaticAccessGrant, then
  # it should be used as the actor.
  def resolve_actor(actor)
    # TODO: update callers to always send a user
    return Promise.resolve(actor) unless actor.is_a?(User)

    if oauth_access = actor.oauth_access
      return oauth_access.async_ability_delegate.then do |ability_delegate|
        ability_delegate.can_have_granular_user_permissions? ? oauth_access : actor
      end
    end

    if programmatic_access = actor.programmatic_access
      grant = programmatic_access.grant_for(actor)
      return Promise.resolve(grant)
    end

    Promise.resolve(actor)
  end

  # Does the actor have access via a special role?
  def async_has_direct_permission?(actor:, action:)
    return Promise.resolve(false) unless actor&.ability_delegate
    return Promise.resolve(false) if actor.ability_delegate.can_have_granular_user_permissions?

    parent.async_adminable_by?(actor)
  end

  # Does the actor have access via granular permission?
  def async_has_granular_user_permission?(actor:, action:)
    return Promise.resolve(false) unless actor&.ability_delegate&.can_have_granular_user_permissions?
    async_has_granular_permission_on_specific_resource?(actor: actor, action: action)
  end

  # Does the actor have a granular permission on this resource?
  def async_has_granular_permission_on_specific_resource?(actor:, action:)
    ::Permissions::Service.async_can?(actor, action, self)
  end

  def application_has_permission?(oauth_access:, action:)
    permissions = oauth_access.application.latest_version.user_permissions
    requested_action = ::Permission.actions[action]
    resource_name = name.to_s
    granted_action = ::Permission.actions[permissions[resource_name]]

    if granted_action && requested_action && requested_action <= granted_action
      Promise.resolve(true)
    else
      Promise.resolve(false)
    end
  end
end
