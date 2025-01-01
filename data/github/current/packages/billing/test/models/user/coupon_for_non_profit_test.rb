# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponForNonProfitTest < GitHub::TestCase
    include GitHub::BillingTest

    test "fails redemption if transaction cannot be refunded" do
      coupon = create(:coupon, code: Coupon::NON_PROFIT_CODE)
      user = create(:user)
      txn = create(:billing_transaction, user: user)

      GitHub::Billing.stubs(:refund_transaction)
        .with(txn.transaction_id)
        .returns(GitHub::Billing::Result.failure("Oops!"))

      result = user.redeem_coupon(coupon)

      refute result
      assert_match /Oops/, user.errors.full_messages.to_sentence
    end

    test "succeeds redemption if most recent transaction already voided" do
      coupon = create(:coupon, code: Coupon::NON_PROFIT_CODE)
      user = create(:user)
      create :billing_transaction,
        user: user,
        last_status: :voided

      assert user.redeem_coupon(coupon)
    end

    test "succeeds redemption if most recent transaction already refunded" do
      coupon = create(:coupon, code: Coupon::NON_PROFIT_CODE)
      user = create(:user)
      sale_transaction = create :billing_transaction, user: user
      create :billing_transaction,
        user: user,
        transaction_type: "refund",
        sale_transaction_id: sale_transaction.transaction_id

      assert user.redeem_coupon(coupon)
    end

    test "succeeds redemption if most recent transaction is more than a year old" do
      # succeeds because we skip refunding if the transaction is more than a year old
      coupon = create(:coupon, code: Coupon::NON_PROFIT_CODE)
      user = create(:user)
      create :billing_transaction,
        user: user,
        created_at: 2.years.ago

      assert user.redeem_coupon(coupon)
      GitHub::Billing.expects(:refund_transaction).never
    end
  end
end
