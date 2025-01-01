# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingTransactionStatusTest < GitHub::TestCase
  fixtures do
    @billing_transaction = create :billing_transaction
  end

  test "#pending_status_update? is true for transactions not in final status" do
    @billing_transaction.last_status = :submitted_for_settlement
    assert @billing_transaction.pending_status_update?

    @billing_transaction.last_status = :settled
    refute @billing_transaction.pending_status_update?
  end

  test "belongs_to association and class_name option are working correctly" do
    status = @billing_transaction.statuses.build
    assert_equal @billing_transaction, status.billing_transaction
  end
end
