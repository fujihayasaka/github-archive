# typed: true
# frozen_string_literal: true

class InteractionLimits::LimitComponent < ApplicationComponent
  include InteractionBanHelper

  # ability - A RepositoryInteractionAbility.
  # limit - A Symbol limit from RepositoryInteractionAbility::INTERACTION_LIMITS.
  # current_limit – A Symbol limit that is the currently active limit for an object.
  # current_origin - A Symbol that is the current origin of an active limit for an object.
  # current_expiry - A DateTime that is the current expiry of an active limit, if one is enabled.
  # staff_actor – A Boolean indicating if this is being rendered in stafftools for a staff user.
  def initialize(
    ability:,
    limit:,
    current_limit:,
    current_origin:,
    current_expiry:,
    in_organization: false,
    staff_actor: false
  )
    @ability         = ability
    @limit           = limit
    @current_limit   = current_limit
    @current_origin  = current_origin
    @current_expiry  = current_expiry
    @in_organization = in_organization
    @staff_actor     = staff_actor
  end

  private

  attr_reader :ability, :limit, :current_limit, :current_origin,
              :current_expiry, :in_organization, :staff_actor

  def render?
    return false unless GitHub.interaction_limits_enabled?
    ability.present? && limit.present? && current_limit.present? && current_origin.present?
  end

  def limit_enabled?
    current_limit == limit
  end

  def overridden_by_global_limit?
    return false unless ability.repository?
    current_origin != :repository
  end

  def limit_title
    case limit
    when :sockpuppet_disallowed
      "Limit to existing users"
    when :contributors_only
      "Limit to prior contributors"
    when :collaborators_only
      "Limit to repository collaborators"
    end
  end

  def limit_description
    interaction_limit_description(ability: ability, limit: limit)
  end

  def show_time_remaining?
    limit_enabled? && !overridden_by_global_limit?
  end

  def durations
    RepositoryInteractionAbility::DURATION_OPTIONS.values
  end

  def limit_enum
    if limit == :sockpuppet_disallowed
      "EXISTING_USERS"
    else
      limit.to_s.upcase
    end
  end

  def form_path
    return stafftools_form_path if staff_actor

    if ability.organization?
      update_org_interaction_limits_path(ability.object)
    elsif ability.user?
      settings_interaction_limits_path
    else
      set_repository_interaction_limit_path(ability.object.owner, ability.object)
    end
  end

  def stafftools_form_path
    if ability.repository?
      stafftools_repository_interaction_limits_path(ability.object.owner, ability.object)
    else
      stafftools_user_interaction_limits_path(ability.object)
    end
  end
end
