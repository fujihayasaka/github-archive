# typed: strict
# frozen_string_literal: true

class Billing::Settings::PaymentMethodInformationComponent < ApplicationComponent
  sig { returns(Billing::Types::Account) }
  attr_reader :target


  sig { params(target: Billing::Types::Account).void }
  def initialize(target:)
    @target = target
  end

  sig { returns(T::Boolean) }
  def render?
    has_unpaid_invoices? || show_auth_and_capture_message?
  end

  sig { returns(T::Boolean) }
  memoize def has_unpaid_invoices?
    target.balance.positive?
  end

  sig { returns(T::Boolean) }
  def show_auth_and_capture_message?
    target.can_be_authorized?(check_payment_method: false, check_overage: false)
  end

  sig { returns(String) }
  def notice_text
    if has_unpaid_invoices?
      "When you update your payment method, any unpaid invoices will be charged."
    else
      "We may place a temporary hold on your payment method to verify its validity. This is not a charge, and it will be released automatically after verification."
    end
  end
end
