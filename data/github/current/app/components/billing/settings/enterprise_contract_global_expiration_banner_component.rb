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
    business.sales_managed_subscription_self_serve_eligible? ? :link : :secondary
  end

  sig { returns(Symbol) }
  def flash_scheme
    :warning
  end

  sig { returns(Symbol) }
  def section_label
    :warn
  end

  sig { returns(String) }
  def banner_message
    message_parts = ["Your GitHub Enterprise contract for ", content_tag(:strong, business.name)]
    if expired?
      message_parts << " has expired."
      message_parts << " You will continue to be billed for metered usage."
    else
      if expires_today?
        message_parts << " expires today."
      else
        message_parts << " expires in " << content_tag(:strong, days_till_expiry)
        message_parts << " on " << content_tag(:strong, billing_end_date) << "."
      end
      message_parts << " You will still be billed for metered usage after your contract expires."
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

  sig { returns(String) }
  def renew_button_text
    return "Renew now" unless business.past_due_invoice?
    return "Pay overdue invoice to renew" if business.eligible_for_renewal?
    "Pay overdue invoice to add more seats"
  end

  sig { returns(String) }
  def renew_button_path
    return billing_renew_enterprise_path(business)  unless business.past_due_invoice?
    return enterprise_billing_payment_information_path(business) if business.billed_via_billing_platform?

    settings_billing_tab_enterprise_path(business, :payment_information)
  end

  sig { params(cta: String).returns(T::Hash[Symbol, String]) }
  def click_tracking_attributes(cta:)
    payload = {
      user_id: current_user.id,
      business_id: business.id,
      days_till_expiry: days_till_expiry,
      expired: expired?,
      past_due_invoice: business.past_due_invoice?,
      action: cta,
      category: "enterprise_contract_global_expiration_banner"
    }
    hydro_click_tracking_attributes("enterprise_contract_global_expiration_banner.click", payload)
  end

  private

  sig { returns(String) }
  def billing_end_date
    business.billing_term_ends_on.strftime("%B %d, %Y")
  end

  sig { returns(String) }
  def days_till_expiry
    pluralize((business.billing_term_ends_on - Date.current).to_i, "day")
  end

  sig { returns(T::Boolean) }
  def expired?
    GitHub::Billing.past?(business.billing_term_ends_on)
  end

  sig { returns(T::Boolean) }
  def expires_today?
    business.billing_term_ends_on == Date.current
  end
end
