# typed: strict
# frozen_string_literal: true

class Billing::Public::Budgets::Permission
  extend T::Sig

  sig { returns(::Business) }
  attr_reader :business

  sig { returns(::User) }
  attr_reader :current_user

  sig { params(business: ::Business, current_user: ::User).void }
  def initialize(business, current_user)
    @business = business
    @current_user = current_user
  end

  sig { returns(T::Boolean) }
  def show_org_level_budgets_tab?
    !!(business.feature_enabled?(:ghe_spending_limits) && show_spending_limit_tab?)
  end

  sig { returns(T::Boolean) }
  def show_enterprise_spending_limit_tab?
    !!(!business.feature_enabled?(:ghe_spending_limits) && show_spending_limit_tab?)
  end

  sig { returns(T::Boolean) }
  def show_marketplace_apps_tab?
    show_billing_privileges?
  end

  sig { returns(T::Boolean) }
  def show_sponsorships_tab?
    !!(business.feature_enabled?(:sponsors_self_serve_enterprise) && show_billing_privileges?)
  end

  sig { returns(T::Boolean) }
  def show_spending_limit_tab?
    show_metered_billing_configuration? || show_billing_privileges?
  end

  sig { returns(T::Boolean) }
  def show_billing_privileges?
    return false unless business.owner?(current_user) || business.billing_manager?(current_user)
    return false unless business.can_self_serve? && !business.invoiced?
    true
  end

  sig { returns(T::Boolean) }
  def show_metered_billing_configuration?
    business.plan_metered_billing_eligible?
  end
end
