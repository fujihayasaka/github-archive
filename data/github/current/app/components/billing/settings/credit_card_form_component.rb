# typed: true
# frozen_string_literal: true

class Billing::Settings::CreditCardFormComponent < ApplicationComponent
  SIGNATURE_VIEW_CONTEXTS = Billing::Zuora::HostedPaymentsPage::SIGNATURE_VIEW_CONTEXTS

  # Creates a Zuora Hosted Payment Page (HPP) for adding/updating a payment method or applying a one-time payment
  #
  # target - User/Org or Business to target
  # plan - String GitHub plan
  # new_name_address_design - Use address collection
  # signature_view_context - String HPP context (one of Billing::Zuora::HostedPaymentsPage::SIGNATURE_VIEW_CONTEXTS)
  # return_to - String path to return client to upon billing info update
  # manual_payment - Boolean Whether a payment should be applied (default: false)
  # invoices - Optional Array of Zuora invoice number Strings to apply the payment to (e.g. ["INV001", "INV002"])
  # payment_gateway - Optional String Zuora payment gateway to use (e.g. "Stripe v3")
  # zuora_redirect_to - String path to return the client to after Zuora submission
  # zuora_post_success_form_selector - Optional String CSS selector for a form to POST after a
  #                                    successful manual payment, instead of navigating to zuora_redirect_to
  # zuora_failure_redirect_to - Optional String path to navigate to when a manual payment can't be
  #                             confirmed in time, instead of navigating to zuora_redirect_to
  # show_payment_method - Boolean whether to display the Zuora HPP
  # modal_view - Boolean whether this component is being rendered in a modal
  # include_modal_chrome - Boolean whether to include CSS classes to style the modal body, when modal_view=true
  # allow_editing - Boolean whether to support updating the payment method
  # allow_removing - Boolean whether to support removing the payment method (default: false)
  # show_auth_notice - Boolean whether to force the authorization hold notice to be shown (default: false)
  def initialize(
    target:,
    plan: nil,
    new_name_address_design: false,
    signature_view_context: nil,
    return_to: nil,
    manual_payment: false,
    card_setup: false,
    invoices: nil,
    payment_gateway: nil,
    zuora_redirect_to: nil,
    zuora_post_success_form_selector: nil,
    zuora_failure_redirect_to: nil,
    show_payment_method: false,
    modal_view: false,
    include_modal_chrome: true,
    allow_editing: true,
    allow_removing: false,
    show_auth_notice: false
  )
    @target = target
    @plan = plan
    @new_name_address_design = new_name_address_design
    @signature_view_context = if signature_view_context
      fetch_or_fallback(SIGNATURE_VIEW_CONTEXTS, signature_view_context, nil)
    end
    @return_to = return_to
    @manual_payment = manual_payment
    @card_setup = card_setup
    @invoices = invoices
    @payment_gateway = payment_gateway
    @zuora_redirect_to = zuora_redirect_to
    @zuora_post_success_form_selector = zuora_post_success_form_selector
    @zuora_failure_redirect_to = zuora_failure_redirect_to
    @show_payment_method = show_payment_method
    @modal_view = modal_view
    @include_modal_chrome = include_modal_chrome
    @allow_editing = allow_editing
    @allow_removing = allow_removing
    @show_auth_notice = show_auth_notice
  end

  private

  attr_reader :target, :plan, :signature_view_context, :zuora_redirect_to, :zuora_post_success_form_selector,
    :zuora_failure_redirect_to, :allow_editing, :allow_removing, :invoices, :payment_gateway

  def render?
    target.present? && GitHub.billing_enabled? && logged_in?
  end

  def return_to
    @return_to || params[:return_to]
  end

  def allow_editing?
    allow_editing
  end

  def allow_removing?
    allow_removing
  end

  def manual_payment?
    @manual_payment
  end

  def card_setup?
    @card_setup
  end

  def show_payment_method?
    @show_payment_method
  end

  def new_name_address_design?
    @new_name_address_design
  end

  def show_auth_notice?
    @show_auth_notice
  end

  def target_billing_settings_path
    if target.user?
      settings_user_billing_path
    elsif target.business?
      settings_billing_enterprise_path(target)
    else
      settings_org_billing_path(target)
    end
  end

  def hide_payment_controls?
    !show_payment_method? && target.has_credit_card?
  end

  memoize def payment_method
    target.payment_method
  end

  def data_collection_enabled?
    signature_view_context.present? && (target.has_saved_billing_information? || target.live_sdn_screening_enabled?)
  end

  def modal_view?
    @modal_view
  end

  sig { returns T::Boolean }
  def include_modal_chrome?
    @include_modal_chrome
  end

  def show_remove_button?
    return false unless allow_removing?
    return false unless customer = target.customer
    customer.payment_method_can_be_removed?.success?
  end

  def account_type
    return "user" if target.user?
    return "organization" if target.organization?
    "enterprise"
  end
end
