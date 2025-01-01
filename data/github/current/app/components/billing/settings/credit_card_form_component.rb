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
  # show_payment_method - Boolean whether to display the Zuora HPP
  # modal_view - Boolean whether this component is being rendered in a modal
  # include_modal_chrome - Boolean whether to include CSS classes to style the modal body, when modal_view=true
  # allow_editing - Boolean whether to support updating the payment method
  def initialize(
    target:,
    plan: nil,
    new_name_address_design: false,
    signature_view_context: nil,
    return_to: nil,
    manual_payment: false,
    invoices: nil,
    payment_gateway: nil,
    zuora_redirect_to: nil,
    show_payment_method: false,
    modal_view: false,
    include_modal_chrome: true,
    allow_editing: true
  )
    @target = target
    @plan = plan
    @new_name_address_design = new_name_address_design
    @signature_view_context = if signature_view_context
      fetch_or_fallback(SIGNATURE_VIEW_CONTEXTS, signature_view_context, nil)
    end
    @return_to = return_to
    @manual_payment = manual_payment
    @invoices = invoices
    @payment_gateway = payment_gateway
    @zuora_redirect_to = zuora_redirect_to
    @show_payment_method = show_payment_method
    @modal_view = modal_view
    @include_modal_chrome = include_modal_chrome
    @allow_editing = allow_editing
  end

  private

  attr_reader :target, :plan, :signature_view_context, :zuora_redirect_to, :allow_editing, :invoices, :payment_gateway

  def render?
    target.present? && GitHub.billing_enabled? && logged_in?
  end

  def return_to
    @return_to || params[:return_to]
  end

  def allow_editing?
    allow_editing
  end

  def manual_payment?
    @manual_payment
  end

  def show_payment_method?
    @show_payment_method
  end

  def new_name_address_design?
    @new_name_address_design
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
end
