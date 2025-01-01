# typed: true
# frozen_string_literal: true

class Billing::Settings::EnterpriseWithOutstandingInvoicesPleasePayComponent < ApplicationComponent
  sig { returns(Business) }
  attr_reader :business

  sig { returns(T::Boolean) }
  attr_reader :force_render

  # @param business [Business] The business we are rendering the component for
  # @param current_user [User] The user viewing the component
  # @param force_render [Boolean] Force rendering of the flash component, even if it doesn't meet the required conditions. This is used to display the component preview test.
  sig { params(business: Business, current_user: User, force_render: T::Boolean).void }
  def initialize(business:, current_user:, force_render: false)
    @business = T.let(business, Business)
    @current_user = T.let(current_user, User)
    @force_render = force_render
  end

  sig { returns(T::Boolean) }
  def render?
    return true if force_render
    return false unless business.feature_enabled?(:ghe_sales_serve_renewals)

    business.past_due_invoice?
  end

  private

  sig { returns(String) }
  def blocked_user_action
    return "renewing" if business.feature_enabled?(:ghe_sales_serve_overdue) && business.eligible_for_renewal?
    "adding more seats"
  end

  sig { returns(T::Boolean) }
  def render_pay_cta?
    return true unless business.feature_enabled?(:ghe_sales_serve_overdue)

    # Hide the "Pay Invoice" button if the user is already on the payment page
    !current_page?(enterprise_billing_url)
  end

  sig { returns(String) }
  def enterprise_billing_url
    return enterprise_billing_payment_information_path(business) if business.billed_via_billing_platform?
    settings_billing_tab_enterprise_path(business, :payment_information)
  end
end
