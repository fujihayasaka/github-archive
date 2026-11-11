# typed: strict
# frozen_string_literal: true

class Billing::Settings::PaymentMethodButtonVnextComponent < ApplicationComponent

  sig { params(account: Billing::Types::Account, allowed_to_update: T::Boolean, return_to: T.nilable(String)).void }
  def initialize(account:, allowed_to_update:, return_to: nil)
    @account = account
    @allowed_to_update = allowed_to_update
    @return_to = return_to
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless account.feature_flag_enabled?(:billing_payment_removal_vnext, default: false)
    allowed_to_update? || show_remove_button?
  end

  sig { returns(T::Boolean) }
  def show_remove_button?
    return false unless customer = account.customer
    customer.payment_method_can_be_removed?.success?
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

  sig { returns(String) }
  def account_type
    return "user" if account.user?
    return "organization" if account.organization?
    "enterprise"
  end

  private

  sig { returns(Billing::Types::Account) }
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

  sig { returns(T::Boolean) }
  def has_payment_method?
    !!payment_method&.valid_payment_token?
  end
end
