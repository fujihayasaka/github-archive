# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Settings::PaymentHistory::PaymentRecordTest < GitHub::BillingTestCase
  context ".payment_records" do
    test "does not include authorization transactions in the results" do
      user = create(:user)
      _auth = create(:billing_transaction, :authorization, user: user)
      sale = create(:billing_transaction, user: user)

      records = Billing::Settings::PaymentHistory::PaymentRecord.payment_records(target: user)

      assert_equal 1, records.size
      payment_record = T.must(records.first)
      assert_equal sale, payment_record.billing_transaction
    end
  end
end
