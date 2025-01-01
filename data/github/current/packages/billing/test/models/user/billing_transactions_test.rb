# typed: true
# frozen_string_literal: true

require "test_helper"

class UserBillingTransactionsTest < GitHub::TestCase
  include GitHub::BillingTest
  include GitHub::BrainTree::TestHelper

  context "attempted transactions" do
    test "destroys all associated line items when destroyed" do
      line_item = create :billing_transaction_line_item
      billing_transaction = line_item.billing_transaction

      assert_difference "Billing::BillingTransaction::LineItem.count", -1 do

        billing_transaction.destroy
      end

      assert_raises ActiveRecord::RecordNotFound do
        line_item.reload
      end
    end
  end
end
