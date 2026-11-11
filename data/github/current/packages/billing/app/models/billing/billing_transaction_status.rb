# typed: true
# frozen_string_literal: true

module Billing
  # Stores a history of transaction statuses (as given by an external processor)
  # for a BillingTransaction
  class BillingTransactionStatus < ApplicationRecord::Domain::Users
    # Public: The BillingTransaction this status belongs to.
    belongs_to :billing_transaction, class_name: "Billing::BillingTransaction"

    enum :status, Billing::BillingTransactionStatuses::ALL
    validates :status, presence: true

    # Internal: Sets various attributes from the values on status_detail
    #
    # status_detail - Instance of Braintree::Transaction::StatusDetail from
    #                 transaction#status_history
    def status_detail=(status_detail)
      self.amount_in_cents    = (BigDecimal(status_detail.amount) * 100).to_i
      self.platform_user      = status_detail.user
      self.status             = status_detail.status.to_sym
      self.transaction_source = status_detail.transaction_source
    end

    # Public: Amount in cents.
    # column :amount_in_cents
    validates_presence_of :amount_in_cents

    # Public: The platform user that initiated this status change.
    # column :platform_user

    # Public: The interface or source the transaction was initiated through.
    # column :transaction_source

    # Public: The timestamp of the status change.
    # column :created_at
  end
end
