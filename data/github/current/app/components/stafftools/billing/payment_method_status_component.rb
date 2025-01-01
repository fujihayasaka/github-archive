# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class PaymentMethodStatusComponent < ApplicationComponent

      sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      def call
        render Stafftools::StatusListItemComponent.new(status: status, message: message,
          test_selector: "payment-method-status", tag: @tag)
      end

      private

      attr_reader :billable_entity

      sig { returns(T::Boolean) }
      memoize def invoiced?
        billable_entity.invoiced?
      end

      sig { returns(T::Boolean) }
      memoize def has_credit_card?
        billable_entity.has_credit_card?
      end

      sig { returns(T::Boolean) }
      memoize def has_paypal_account?
        billable_entity.has_paypal_account?
      end

      sig { returns(T::Boolean) }
      memoize def has_blocklisted_payment_method?
        return false unless has_credit_card?
        billable_entity.payment_method.blocklisted?
      end

      sig { returns(T::Boolean) }
      memoize def has_azure_subscription?
        billable_entity.linked_azure_subscription?
      end

      sig { returns(Symbol) }
      def status
        if has_blocklisted_payment_method?
          :error
        elsif invoiced? || has_credit_card? || has_paypal_account?
          :success
        else
          :neutral
        end
      end

      sig { returns(String) }
      def message
        if has_azure_subscription?
          "Payment method: Azure metered subscription"
        elsif invoiced?
          "Payment method: Invoice"
        elsif has_blocklisted_payment_method?
          "Payment method: Blocklisted credit or debit card"
        elsif has_credit_card?
          "Payment method: Credit or debit card"
        elsif has_paypal_account?
          "Payment method: PayPal"
        else
          "Payment method: No card on file"
        end
      end
    end
  end
end
