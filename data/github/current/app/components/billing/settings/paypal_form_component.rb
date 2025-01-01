# typed: true
# frozen_string_literal: true

# Public: This component renders the fields for PayPal.
class Billing::Settings::PaypalFormComponent < ApplicationComponent
  SIGNATURE_VIEW_CONTEXTS = Billing::Zuora::HostedPaymentsPage::SIGNATURE_VIEW_CONTEXTS

  # target - The User/Organization/Business that owns the payment method
  # plan - a GitHub::Plan, the String name of one, or nil
  # signature_view_context - optional String
  def initialize(target:,
                 plan: nil,
                 signature_view_context: nil,
                 new_name_address_design: false,
                 hide_billing_info_fields: false,
                 return_to: nil,
                 allow_editing: true)
    @target = target
    @plan = plan
    @new_name_address_design = new_name_address_design
    @hide_billing_info_fields = hide_billing_info_fields
    @return_to = return_to
    @allow_editing = allow_editing
    @signature_view_context = if signature_view_context
      fetch_or_fallback(SIGNATURE_VIEW_CONTEXTS, signature_view_context, nil)
    end
  end

  private

  attr_reader :target, :return_to, :plan, :signature_view_context, :allow_editing

  def render?
    GitHub.billing_enabled? && target.present? && logged_in?
  end

  def allow_editing?
    allow_editing
  end

  def new_name_address_design?
    @new_name_address_design
  end

  def hide_billing_info_fields?
    @hide_billing_info_fields
  end

  def form_class
    if new_name_address_design?
      "js-paypal-payment-method-form"
    else
      ""
    end
  end

  def show_auth_and_capture_message?
    target.can_be_authorized?(check_payment_method: false, check_overage: false)
  end

  memoize def new_design_and_has_paypal?
    new_name_address_design? && target.has_paypal_account?
  end
end
