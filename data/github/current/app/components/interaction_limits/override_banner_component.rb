# typed: true
# frozen_string_literal: true

class InteractionLimits::OverrideBannerComponent < ApplicationComponent
  include InteractionBanHelper

  DEFAULT_TYPE = :banner
  TYPE_OPTIONS = [DEFAULT_TYPE, :header]

  def initialize(
    object:,
    type: DEFAULT_TYPE,
    interaction_ability: nil,
    current_origin: nil,
    limit_owner: nil,
    current_limit: nil,
    current_expiry: nil,
    return_to: nil,
    **kwargs
  )
    @object = object
    @type = fetch_or_fallback(TYPE_OPTIONS, type, DEFAULT_TYPE)
    @interaction_ability = interaction_ability
    @current_origin = current_origin
    @limit_owner = limit_owner
    @current_limit = current_limit
    @current_expiry = current_expiry
    @return_to = return_to
    @kwargs = kwargs
  end

  private

  attr_reader :object, :return_to

  def render?
    return false unless GitHub.interaction_limits_enabled?
    return false unless object.present?
    return false if interaction_ability.repository? && object.private?
    return false unless object.can_set_interaction_limits?(current_user)

    active_override?
  end

  memoize def interaction_ability
    @interaction_ability || RepositoryInteractionAbility.new(object)
  end

  def active_override?
    return false if current_limit == :no_limit
    current_origin != :repository
  end

  memoize def current_origin
    @current_origin || interaction_ability.active_limit_origin
  end

  memoize def current_limit
    @current_limit || interaction_ability.overall_active_limit
  end

  memoize def limit_owner
    @limit_owner || interaction_ability.repository? ? object.owner : object
  end

  memoize def current_expiry
    @current_expiry || interaction_ability.overall_active_limit_expiry
  end

  def limit_title
    limit_name = case current_limit
    when :sockpuppet_disallowed
      "existing users"
    when :contributors_only
      "prior contributors"
    when :collaborators_only
      "collaborators"
    end

    limit_owner_word = in_organization? ? limit_owner.display_login : "your account"

    "Public repositories in #{limit_owner_word} are currently limited to #{limit_name}"
  end

  def limit_description
    interaction_limit_description(ability: interaction_ability, limit: current_limit)
  end

  def in_organization?
    limit_owner.organization?
  end

  def form_path
    if in_organization?
      update_org_interaction_limits_path(limit_owner)
    else
      settings_interaction_limits_path
    end
  end

  def adminable?
    limit_owner.can_set_interaction_limits?(current_user)
  end

  def admin_link
    if in_organization?
      org_interaction_limits_path(limit_owner)
    else
      settings_interaction_limits_path
    end
  end

  def admin_text
    if in_organization?
      "organization settings"
    else
      "interaction limit settings"
    end
  end

  def banner?
    @type == :banner
  end
end
