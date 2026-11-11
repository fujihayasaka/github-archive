# typed: strict
# frozen_string_literal: true

class Billing::Settings::PaymentMethodInformationComponent < ApplicationComponent
  sig { returns(Billing::Types::Account) }
  attr_reader :target

  sig { returns(Symbol) }
  attr_reader :payment_type

  sig { returns(T::Boolean) }
  attr_reader :show_auth_notice

  sig { returns(T::Boolean) }
  attr_reader :hide_update_notices

  # @param show_auth_notice [Boolean] When true, forces the authorization hold notice to be shown if the account can be authorized.
  # @param hide_update_notices [Boolean] When true, hides messages related to updating the payment method.
  sig { params(target: Billing::Types::Account, payment_type: Symbol, show_auth_notice: T::Boolean, hide_update_notices: T::Boolean).void }
  def initialize(target:, payment_type:, show_auth_notice: false, hide_update_notices: false)
    @target = target
    @payment_type = payment_type
    @show_auth_notice = show_auth_notice
    @hide_update_notices = hide_update_notices
  end

  sig { returns(T::Boolean) }
  def render?
    show_separate_auth_notice? || show_payment_method_verification_message? || show_prepaid_cards_not_supported_message?
  end

  sig { returns(T::Boolean) }
  def show_separate_auth_notice?
    show_auth_notice && can_be_authorized?
  end

  sig { returns(T::Boolean) }
  def show_payment_method_verification_message?
    has_unpaid_invoices? || (!show_auth_notice && can_be_authorized?)
  end

  sig { returns(T::Boolean) }
  def show_prepaid_cards_not_supported_message?
    payment_type == :credit_card
  end

  sig { returns(T::Boolean) }
  memoize def has_unpaid_invoices?
    target.balance.positive?
  end

  sig { returns(T::Boolean) }
  memoize def can_be_authorized?
    target.can_be_authorized?(check_payment_method: false, check_overage: false)
  end

  sig { returns(String) }
  def payment_method_verification_message
    if has_unpaid_invoices?
      unpaid_invoices_message
    else
      authorization_hold_message
    end
  end

  sig { returns(String) }
  def unpaid_invoices_message
    "When you update your payment method, any unpaid invoices will be charged."
  end

  sig { returns(String) }
  def authorization_hold_message
    "We may place a temporary hold on your payment method to verify its validity. This is not a charge, and it will be released automatically after verification."
  end

  sig { returns(String) }
  def prepaid_cards_not_supported_message
    "Prepaid debit and credit cards are not accepted as a valid form of payment."
  end
end
