# typed: true
# frozen_string_literal: true

module Stafftools::Billing::History
  class BillingTransactionActionsComponent < ApplicationComponent
    extend T::Sig

    include Stafftools::BillingHelper

    attr_reader :payment

    sig { params(payment: Stafftools::Billing::PaymentRecord).void }
    def initialize(payment:)
      @payment = payment
    end

    sig { returns(T::Boolean) }
    def show_actions_dropdown?
      payment.show_receipt_link? || payment.refundable? || payment.is_authorization?
    end

    private def render?
      show_actions_dropdown?
    end
  end
end
