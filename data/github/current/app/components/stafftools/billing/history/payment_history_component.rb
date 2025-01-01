# typed: true
# frozen_string_literal: true

module Stafftools::Billing::History
  class PaymentHistoryComponent < ApplicationComponent

    attr_reader :payments, :billable_entity

    sig { returns(T.nilable(Billing::BillingTransaction)) }
    attr_reader :latest_authorization

    sig do
      params(
        payments: T::Array[Stafftools::Billing::PaymentRecord],
        billable_entity: T.any(User, Business)
      ).void
    end
    def initialize(payments:, billable_entity:)
      @payments = payments
      @billable_entity = billable_entity
      if customer = billable_entity.customer
        @latest_authorization = Billing::BillingTransaction.current_authorizations_for_customer(
          customer.id
        ).last
      end
    end

    sig { returns(T::Boolean) }
    def show_last_failed_auth_retry?
      !!latest_authorization&.failed? && billable_entity.payment_method_supports_authorization?
    end
  end
end
