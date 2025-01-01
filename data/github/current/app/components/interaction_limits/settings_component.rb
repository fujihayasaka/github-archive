# typed: true
# frozen_string_literal: true

class InteractionLimits::SettingsComponent < ApplicationComponent

  def initialize(object:, staff_actor: false)
    @object      = object
    @staff_actor = staff_actor
  end

  private

  attr_reader :object, :staff_actor

  def render?
    return false unless GitHub.interaction_limits_enabled?
    object.present?
  end

  memoize def interaction_ability
    RepositoryInteractionAbility.new(object)
  end

  memoize def current_limit
    interaction_ability.overall_active_limit
  end

  memoize def current_origin
    interaction_ability.active_limit_origin
  end

  memoize def current_expiry
    interaction_ability.overall_active_limit_expiry
  end

  memoize def owner
    repository? ? object.owner : object
  end

  def repository?
    object.is_a?(Repository)
  end

  def show_override_banner?
    return false unless repository?
    current_origin != :repository
  end

  def show_global_settings_header?
    return false unless repository?
    return false if show_override_banner?

    owner.can_set_interaction_limits?(current_user)
  end

  def global_settings_phrase
    owner.organization? ? "the #{owner.display_login} organization" : "your account"
  end

  def global_settings_text
    owner.organization? ? "organization settings" : "account settings"
  end

  def global_settings_link
    owner.organization? ? org_interaction_limits_path(owner) : settings_interaction_limits_path
  end
end
