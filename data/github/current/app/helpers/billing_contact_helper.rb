# typed: strict
# frozen_string_literal: true

module BillingContactHelper
  include GitHub::Memoizer
  extend T::Helpers

  abstract!

  sig { abstract.returns(Billing::Types::Account) }
  def account; end

  sig { returns(T::Boolean) }
  memoize def has_saved_billing_information?
    account.has_saved_billing_information?
  end

  sig { returns(T::Boolean) }
  def is_allowed_to_edit_billing_information?
    return false unless has_saved_billing_information?
    account.is_allowed_to_edit_billing_information?
  end

  sig { returns(T::Boolean) }
  def is_allowed_to_remove_billing_information?
    return false unless has_saved_billing_information?
    account.is_allowed_to_remove_billing_information?
  end

  sig { returns(T::Boolean) }
  def valid_for_trade_screening?
    account.billing_contact.valid_for_trade_screening?
  end
end
