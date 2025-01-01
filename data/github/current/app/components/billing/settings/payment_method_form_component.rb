# typed: true
# frozen_string_literal: true

class Billing::Settings::PaymentMethodFormComponent < ApplicationComponent

  # target - The User/Organization/Business that owns the payment method
  def initialize(
    target:,
    new_name_address_design: false,
    signature_view_context: nil,
    return_to: nil,
    show_payment_method: false,
    plan: nil,
    modal_view: false,
    include_modal_chrome: true,
    include_paypal: true
  )
    @target = target
    @new_name_address_design = new_name_address_design
    @signature_view_context = signature_view_context
    @return_to = return_to
    @show_payment_method = show_payment_method
    @plan = plan
    @modal_view = modal_view
    @include_modal_chrome = include_modal_chrome
    @include_paypal = include_paypal
  end

  private

  attr_reader :target, :signature_view_context, :plan, :allow_editing, :include_paypal

  alias :include_paypal? :include_paypal

  def render?
    GitHub.billing_enabled? && logged_in? && target.present?
  end

  def return_to
    @return_to || params[:return_to]
  end

  def modal_view?
    @modal_view
  end

  sig { returns T::Boolean }
  def include_modal_chrome?
    @include_modal_chrome
  end

  memoize def hide_payment_controls?
    new_name_address_design? && !show_payment_method? && target.has_valid_payment_method?
  end

  def new_name_address_design?
    @new_name_address_design
  end

  def allow_editing?
    return false unless target.has_valid_payment_method?(feature_type: :noncommercial)
    return true unless target.org_is_on_standard_tos?
    return true unless target.has_linked_billing_contact?

    target.has_linked_billing_contact_to_actor?(actor: current_user)
  end

  def show_payment_method?
    @show_payment_method
  end

  memoize def zuora_maintenance_enabled?
    FeatureFlag.vexi.enabled?(:zuora_maintenance, target, default: false)
  end

  memoize def has_paypal_account?
    target.has_paypal_account?
  end

  memoize def has_azure_subscription?
    target.customer&.azure_subscription_id.present?
  end

  # Public: Indicates if we should show Paypal as a payment option.
  #         Both options should be shown if the target is disabled by RBI AND if they have an existing
  #         paypal method to allow them to change their payment method.
  #
  # Returns a Boolean.
  memoize def show_paypal_option?
    return false unless include_paypal?
    return true unless target.autopay_disabled_by_india_rbi?
    has_paypal_account?
  end

  memoize def show_azure_option?
    return false unless target.business?
    return false unless target.metered_ghe?
    true
  end

  memoize def payment_method
    if show_paypal_option? && has_paypal_account?
      "paypal"
    elsif has_azure_subscription? && show_azure_option?
      "azure"
    else
      "credit_card"
    end
  end

  def credit_card_selected?
    payment_method == "credit_card"
  end

  def paypal_selected?
    payment_method == "paypal"
  end

  def azure_selected?
    payment_method == "azure"
  end
end
