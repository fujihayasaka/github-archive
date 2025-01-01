# typed: true
# frozen_string_literal: true

module Stafftools::Billing::History
  class PaymentHistoryComponent < ApplicationComponent
    extend T::Sig

    attr_reader :payments, :billable_entity

    sig do
      params(
        payments: T::Array[Stafftools::Billing::PaymentRecord],
        billable_entity: T.any(User, Business)
      ).void
    end
    def initialize(payments:, billable_entity:)
      @payments = payments
      @billable_entity = billable_entity
    end
  end
end
