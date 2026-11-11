# typed: strict
# frozen_string_literal: true

class Businesses::EnterpriseCloudOnboarding::AddOnsComponent < ApplicationComponent
  include ApplicationComponent::Rescuable

  rescue_from StandardError, with: :nothing

  sig { returns T.nilable(Business) }
  attr_reader :business

  sig { returns T.nilable(User) }
  attr_reader :user

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig do
    params(
      business: T.nilable(Business),
      user: T.nilable(User),
      system_arguments: Primer::SystemArgumentsValue).void
  end
  def initialize(business: nil, user: nil, **system_arguments)
    @business = business
    @user = user
    @system_arguments = system_arguments
  end

  sig { returns T::Boolean }
  def render?
    return false unless @business
    return false unless @user
    return false unless @business.adminable_by?(@user)
    return false unless potentially_trial_or_purchase_advanced_security? # includes enterprise/emu checks
    return false unless show_start_a_trial? || show_view_onboarding?
    true
  end

  sig { returns T::Boolean }
  memoize def show_start_a_trial?
    eligible_for_self_serve_advanced_security_trial?
  end

  sig { returns T::Boolean }
  memoize def show_view_onboarding?
    has_active_advanced_security_trial? && !!organization_for_advanced_security_trial
  end

  sig { returns T::Boolean }
  memoize def potentially_trial_or_purchase_advanced_security?
    return false unless @business
    @business.potentially_trial_or_purchase_advanced_security?
  end

  sig { returns T::Boolean }
  memoize def eligible_for_self_serve_advanced_security_trial?
    return false unless @business
    @business.eligible_for_self_serve_advanced_security_trial?(skip_shared_checks: true)
  end

  sig { returns T::Boolean }
  memoize def has_active_advanced_security_trial?
    return false unless @business
    @business.has_active_advanced_security_trial?
  end

  sig { returns T.nilable(Organization) }
  memoize def organization_for_advanced_security_trial
    return nil unless @business
    return nil unless @user
    @business.organization_for_advanced_security_trial(actor: @user)
  end

  sig { returns Integer }
  memoize def advanced_security_trial_length
    return 30 unless @business
    @business.new_advanced_security_trial_days
  end
end
