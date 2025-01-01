# typed: strict
# frozen_string_literal: true

class Billing::Settings::EnterpriseContractEarlyExpirationBannerComponent < ApplicationComponent

  DISMISSAL_LENGTH = T.let(30.days, ActiveSupport::Duration)

  sig { returns(Business) }
  attr_reader :business

  sig { returns(User) }
  attr_reader :current_user

  sig { returns(T::Boolean) }
  attr_reader :force_render

  sig { params(business: Business, current_user: User, force_render: T::Boolean).void }
  def initialize(business:, current_user:, force_render: false)
    @business = business
    @current_user = current_user
    @force_render = force_render
  end

  sig { returns(T::Boolean) }
  memoize def business_adminable_by_user?
    business.adminable_by?(current_user)
  end

  sig { returns(String) }
  def notice_name
    "sales_serve_enterprise_contract_expiration"
  end

  sig { returns(T.nilable(Time)) }
  def dismissal_period
    DISMISSAL_LENGTH.from_now
  end

  sig { returns(T::Boolean) }
  def render?
    return true if force_render

    return false unless business.feature_enabled?(:ghe_sales_serve_renewals)
    return false unless business.invoiced?
    return false unless show_banner?
    return false unless business.eligible_for_renewal?
    return false if business.in_renewal_window?(short_window: true)     # global notice takes over
    return false unless business.sales_managed_subscription_self_serve_eligible?
    return false if business.past_due_invoice?

    !Growth::NoticeDismissal.new(current_user).dismissed_business_notice?(notice_name, business_id: T.cast(business.id, Integer))
  end

  sig { returns(T::Boolean) }
  memoize def is_billing_manager?
    business.billing_manager?(current_user)
  end

  sig { returns(T::Boolean) }
  def show_banner?
    business_adminable_by_user? || is_billing_manager?
  end

  sig { returns(String) }
  def billing_end_date
    business.billing_term_ends_on.strftime("%B %d, %Y")
  end

  sig { returns(Integer) }
  def days_to_expiration
    (business.billing_term_ends_on - GitHub::Billing.now.to_date).to_i
  end

  private

  sig { returns(T.nilable(Symbol)) }
  def expiration_status
    :attention
  end
end
