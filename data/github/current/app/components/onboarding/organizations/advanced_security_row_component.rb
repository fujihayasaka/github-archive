# typed: strict
# frozen_string_literal: true

class Onboarding::Organizations::AdvancedSecurityRowComponent < ApplicationComponent
  include AdvancedSecurityEntrypointHelper
  include ApplicationComponent::Rescuable

  rescue_from StandardError, with: :nothing

  VARIANT_MAPPINGS = T.let({
    show_onboarding: {
      title_spacing: 2,
      badge_classes: ""
    },
    show_videos: {
      title_spacing: 4,
      badge_classes: "mt-3"
    },
  }, T::Hash[Symbol, T::Hash[Symbol, T.any(String, Integer)]])

  sig { returns(T.nilable(::Organization)) }
  attr_reader :organization

  sig { returns(T.nilable(User)) }
  attr_reader :user

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig { params(organization: T.nilable(::Organization), user: T.nilable(User), system_arguments: T.untyped).void }
  def initialize(organization:, user:, **system_arguments)
    @organization = organization
    @user = user
    @system_arguments = system_arguments
  end

  sig { returns(T::Boolean) }
  def render?
    show_advanced_security_onboarding? || display_mode != :do_not_show
  end

  sig { returns(T::Boolean) }
  def show_self_serve_cta?
    display_mode == :self_serve
  end

  sig { returns(Symbol) }
  memoize def display_mode
    show_advanced_security_entrypoint?(organization: organization, user: user)
  end

  sig { returns(T::Boolean) }
  memoize def show_advanced_security_onboarding?
    return false unless @organization
    return false unless business = @organization.business
    return false unless @organization.adminable_by?(user)
    business.has_active_advanced_security_trial?
  end

  sig { returns(T::Hash[Symbol, T.any(String, Integer)]) }
  def get_variant
    variant = show_advanced_security_onboarding? ? :show_onboarding : :show_videos
    T.must(VARIANT_MAPPINGS[variant])
  end
end
