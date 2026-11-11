# typed: strict
# frozen_string_literal: true

class Billing::Settings::PaymentMethodButtonComponent < ApplicationComponent

  sig { params(account: T.any(User, Organization), allowed_to_update: T::Boolean, return_to: T.nilable(String)).void }
  def initialize(account:, allowed_to_update:, return_to: nil)
    @account = account
    @allowed_to_update = allowed_to_update
    @return_to = return_to
  end

  sig { returns(T::Boolean) }
  def render?
    return false if account.feature_flag_enabled?(:billing_payment_removal_vnext, default: false)

    allowed_to_update? || show_remove_button?
  end

  sig { returns(T::Boolean) }
  def show_remove_button?
    return false unless has_payment_method?

    no_upcoming_charges = account.no_upcoming_charges?
    customer = account.customer

    GitHub.logger.info(
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.billing.billable_entity.billed_on": account.billed_on,
      "gh.billing.billable_entity.billing_attempts": account.billing_attempts,
      "gh.billing.billable_entity.disabled": account.disabled?,
      "gh.billing.billable_entity.id": account.id,
      "gh.billing.billable_entity.login": account.display_login,
      "gh.billing.billable_entity.type": account.class.name,
      "gh.billing.billable_entity.payment_amount": account.payment_amount(include_metered_usage: false),
      "gh.billing.billable_entity.balance": account.balance,
      "gh.billing.no_upcoming_charges": no_upcoming_charges,
      "gh.billing.customer.id": customer&.id,
      "gh.billing.customer.payment_method_can_be_removed?": customer&.payment_method_can_be_removed?,
    )

    no_upcoming_charges
  end

  sig { returns(T::Boolean) }
  def has_payment_method?
    !!payment_method&.valid_payment_token?
  end

  sig { returns(String) }
  def edit_button_text
    has_payment_method? ? "Edit" : "Add"
  end

  sig { returns(String) }
  def edit_button_aria_label
    has_payment_method? ? "Edit payment method" : "Add payment method"
  end

  sig { returns(String) }
  def edit_button_classes
    "js-edit-payment-method-btn #{'js-skip-billing-info' if account.has_valid_payment_method?}"
  end

  private

  sig { returns(T.any(User, Organization)) }
  attr_reader :account

  sig { returns(T::Boolean) }
  attr_reader :allowed_to_update

  sig { returns(T.nilable(String)) }
  attr_reader :return_to

  alias_method :allowed_to_update?, :allowed_to_update

  sig { returns(T.untyped) }
  def payment_method
    account.payment_method
  end
end
