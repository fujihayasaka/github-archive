# typed: true
# frozen_string_literal: true

class Sponsors::Sponsorables::PaymentMethodFormComponent < ApplicationComponent
  # target - The User/Organization/Business that owns the payment method
  def initialize(target:)
    @target = target
  end

  private

  attr_reader :target

  def render?
    GitHub.billing_enabled? && logged_in? && target.present?
  end

  def signature_view_context
    Billing::Zuora::HostedPaymentsPage::SPONSORS_SIGNATURE_VIEW_CONTEXT
  end

  def new_name_address_design?
    true
  end

  def data_collection_enabled?
    target.user?
  end

  def allow_editing?
    return false unless target.has_valid_payment_method?(feature_type: :noncommercial)
    !target.org_is_on_standard_tos? ||
      !target.has_linked_billing_contact? ||
      target.has_linked_billing_contact_to_actor?(actor: current_user)
  end

  memoize def zuora_maintenance_enabled?
    GitHub.flipper[:zuora_maintenance].enabled?(target)
  end

  def edit_payment_method_classes
    class_names(
      "js-payment-method",
      "js-enter-new-card" => target.has_credit_card?
    )
  end
end
