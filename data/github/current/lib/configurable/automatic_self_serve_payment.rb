# typed: strict
# frozen_string_literal: true

module Configurable
  module AutomaticSelfServePayment
    extend T::Helpers

    requires_ancestor { Business }

    KEY = "automatic_self_serve_payment"

    # Raised when business billing type is not "card".
    class IncorrectBillingType < StandardError; end

    # Raised when the account is ineligiible to have auto-pay enabled.
    class IneligibleAccount < StandardError; end

    # Raised when updating the customer account in Zuora fails.
    class ZuoraUpdateFailed < StandardError; end

    sig { returns(T::Boolean) }
    def can_enable_automatic_self_serve_payment?
      customer = self.customer
      return false unless customer.present?

      (customer.auto_pay_reasons - Customer::AUTO_PAY_DISABLE_REASONS_ALLOWED_FOR_ENABLE).empty?
    end

    sig { params(actor: ::User, update_zuora_account: T::Boolean, reason: Symbol).returns(T::Boolean) }
    def enable_automatic_self_serve_payment(actor, update_zuora_account: true, reason: :customer_initiated)
      T.bind(self, Business)

      unless self.self_serve_payment?
        raise IncorrectBillingType.new "Automatic payments of bills can only be enabled on a self-serve billing enterprise."
      end

      unless can_enable_automatic_self_serve_payment?
        raise IneligibleAccount.new "Automatic payment cannot currently be enabled on your account. Please contact support."
      end

      if update_zuora_account
        # Set AutoPay: true on the Zuora account
        result = Billing::AutoPay.enable! account: self, actor: actor, reason: reason

        if result&.failed?
          raise ZuoraUpdateFailed.new "Saving automatic payment settings failed. Please try again."
        end
      end

      config.enable(KEY, actor)
    end

    sig { params(actor: ::User, reason: T.any(String, Symbol)).returns(T::Boolean) }
    def disable_automatic_self_serve_payment(actor, reason: :customer_initiated)
      # Set AutoPay: false on the Zuora account
      result = self.disable_auto_pay!(reason, actor: actor)
      if result&.failed?
        raise ZuoraUpdateFailed.new "Saving automatic payment settings failed. Please try again."
      end

      config.disable(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def automatic_self_serve_payment_enabled?
      return false unless self.eligible_for_self_serve_payment?
      return false if config.get(KEY).nil?

      config.enabled?(KEY)
    end
  end
end
