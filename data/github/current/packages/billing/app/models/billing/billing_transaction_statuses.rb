# typed: true
# frozen_string_literal: true

module Billing
  module BillingTransactionStatuses
    ALL = {
      authorized: 0,
      failed: 1,
      gateway_rejected: 2,
      processor_declined: 3,
      submitted_for_settlement: 4,
      settled: 5,
      voided: 6,
      settling: 7,
      authorization_expired: 8,
      charged_back: 9,
      authorizing: 10,
      settlement_declined: 11,
      settlement_pending: 12,
      credit_balance_adjusted: 13,
      authorization_cancelled: 14,
    }.with_indifferent_access.freeze

    FINAL = ALL.slice(
      :failed,
      :gateway_rejected,
      :processor_declined,
      :settled,
      :voided,
      :authorization_expired,
      :charged_back,
      :settlement_declined,
      :authorization_cancelled,
    ).freeze

    SUCCESS = ALL.slice(
      :submitted_for_settlement,
      :settling,
      :settled,
      :charged_back,
      :credit_balance_adjusted,
      :authorized,
      :authorization_cancelled,
    ).freeze

    def self.success?(status)
      SUCCESS.values.include?(status)
    end
  end
end
