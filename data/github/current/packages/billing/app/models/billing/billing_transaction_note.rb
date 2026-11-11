# typed: true
# frozen_string_literal: true

module Billing

  # When there is an issue with a billing transaction a note should be added.
  # Examples include:
  #
  #   * transaction was not created at the time of sale and had to be imported
  #   * refund was issued outside of Stafftools
  #   * one-time charge was created outside of Stafftools
  #   * a discrepancy is found during an audit
  #
  class BillingTransactionNote < ApplicationRecord::Domain::Users
    # Public: The BillingTransaction this note belongs to.
    # column :billing_transaction_id
    belongs_to :billing_transaction, class_name: "Billing::BillingTransaction"
    validates_presence_of :billing_transaction_id

    # Public: Note text.
    # column :note
    # Returns a String.
    validates_presence_of :note

    # Public: Created at timestamp.
    # column :created_at
    # Returns an ActiveSupport::TimeWithZone.
  end
end
