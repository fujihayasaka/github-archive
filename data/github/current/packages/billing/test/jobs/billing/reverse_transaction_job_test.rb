# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::ReverseTransactionJobTest < GitHub::BillingTestCase
  test "executes void or refund transaction" do
    transaction = create(:billing_transaction)

    GitHub::Billing.expects(:refund_transaction).with(transaction.transaction_id, skip_email: false)

    ::Billing::ReverseTransactionJob.perform_now(transaction)
  end
end
