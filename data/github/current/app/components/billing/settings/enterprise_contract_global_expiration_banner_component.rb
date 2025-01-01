# typed: strict
# frozen_string_literal: true

class Billing::Settings::EnterpriseContractGlobalExpirationBannerComponent < ApplicationComponent

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

  sig { returns(Symbol) }
  def button_scheme
    expired? ? :secondary : :link
  end

  sig { returns(Symbol) }
  def flash_scheme
    expired? ? :danger : :warning
  end

  sig { returns(Symbol) }
  def section_label
    expired? ? :error : :warn
  end

  sig { returns(String) }
  def banner_message
    message_parts = ["Your GitHub Enterprise contract for ", content_tag(:strong, business.name)]
    if expired?
      message_parts << " is expired. Renew now to keep your experience as smooth as possible."
    else
      message_parts << " expires on " << content_tag(:strong, billing_end_date) << ". Renew now to keep your experience as smooth as possible."
    end
    safe_join(message_parts)
  end

  sig { returns(T::Boolean) }
  def render?
    return true if force_render

    return false unless business.invoiced?
    return false unless show_banner?
    return false unless business.eligible_for_renewal?
    return false unless business.in_renewal_window?(short_window: true)
    return false unless business.sales_managed_subscription_self_serve_eligible?
    return false if business.feature_enabled?(:ghe_sales_serve_overdue) && business.past_due_invoice?

    true
  end

  sig { returns(T::Boolean) }
  memoize def is_billing_manager?
    business.billing_manager?(current_user)
  end

  sig { returns(T::Boolean) }
  memoize def business_adminable_by_user?
    business.adminable_by?(current_user)
  end

  sig { returns(T::Boolean) }
  def show_banner?
    business_adminable_by_user? || is_billing_manager?
  end

  private

  sig { returns(String) }
  def billing_end_date
    business.billing_term_ends_on.strftime("%B %d, %Y")
  end

  sig { returns(T::Boolean) }
  def expired?
    GitHub::Billing.past?(business.billing_term_ends_on)
  end
end
