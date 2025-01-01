# typed: strict
# frozen_string_literal: true

class Businesses::Billing::AdvancedSecurity::StartFreeTrialComponent < ApplicationComponent
  include TradeControlsHelper

  sig { returns(Business) }
  attr_reader :business

  sig { returns(User) }
  attr_reader :user

  sig { params(business: Business, user: User).void }
  def initialize(business:, user:)
    @business = business
    @user = user
  end

  sig { returns(T::Boolean) }
  memoize def advanced_security_trial_eligible?
    business.eligible_for_self_serve_advanced_security_trial?(skip_shared_checks: true)
  end

  sig { returns(T::Boolean) }
  memoize def show_buy_button?
    business.eligible_for_self_serve_advanced_security?(skip_shared_checks: true) && buy_button_path.present?
  end

  sig { returns(String) }
  memoize def buy_button_path
    return billing_settings_advanced_security_upgrade_enterprise_path(business) if business.eligible_for_self_serve_payment?
    return billing_renew_enterprise_path(business) if business.eligible_for_renewal?
    return billing_add_seats_enterprise_path(business) if business.eligible_for_upgrade?
    ""
  end

  sig { returns(T::Boolean) }
  def show_warning_no_orgs?
    business.filtered_organizations(viewer: user).empty?
  end

  sig { returns(T.nilable(String)) }
  def return_to
    organization_onboarding_advanced_security_path(organization_to_redirect_to) unless organization_to_redirect_to.nil?
  end

  sig { returns(T.nilable(String)) }
  def get_started_org_path
    organization_settings_path(organization_to_redirect_to) unless organization_to_redirect_to.nil?
  end

  sig { returns Integer }
  memoize def trial_length
    @business.new_advanced_security_trial_days
  end

  sig { returns(T::Boolean) }
  memoize def has_trade_screening_restriction?
    @business.has_trade_screening_restriction? || @user.has_trade_screening_restriction? || @user.spammy?
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  memoize def trade_screening_error
    trade_screening_cannot_proceed_error_data(target: @business, check_for_current_user: true)
  end

  private

  sig { returns(T.nilable(Organization)) }
  memoize def organization_to_redirect_to
    business.organization_for_advanced_security_trial(actor: user)
  end
end
