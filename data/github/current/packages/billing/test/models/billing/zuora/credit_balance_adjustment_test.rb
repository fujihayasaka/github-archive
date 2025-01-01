# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::CreditBalanceAdjustmentTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  setup do
    @created_date = "2018-03-13T09:33:47.000-07:00"
    @cba = Billing::Zuora::CreditBalanceAdjustment.new({
      "Number" => "CBA-0123456",
      "Amount" => 25,
      "CreatedDate" => @created_date
    })
  end

  context ".find" do
    test "loads the credit balance adjustment from Zuora" do
      with_live_zuora("zuora/get_credit_balance_adjustment_by_id") do
        id = "2c92c0f8748a8d3c01749388f597514a"
        cba = Billing::Zuora::CreditBalanceAdjustment.find(id)

        assert_instance_of Billing::Zuora::CreditBalanceAdjustment, cba
        assert_equal id, cba.id
      end
    end

    test "raises when a CBA doesn't exist in Zuora" do
      with_live_zuora("zuora/get_credit_balance_adjustment_by_id") do
        assert_raises Zuorest::HttpError, "HTTP 404: Not Found" do
          Billing::Zuora::CreditBalanceAdjustment.find("doesnotexist")
        end
      end
    end
  end

  test "#reference_id is the CBA number" do
    # This is to ensure we can tell them apart from other Zuora IDs
    assert_equal @cba.reference_id, @cba.number
  end

  test "#amount is the amount from Zuora" do
    assert_equal 25.0, @cba.amount
  end

  test "#amount_in_cents is the amount from Zuora in cents" do
    assert_equal 2500, @cba.amount_in_cents
  end

  test "#created_at is the date from Zuora" do
    assert_equal Time.parse(@created_date), @cba.created_date
  end

  test "#invoices returns an array of invoices the CBA was applied to" do
    # The name of the method is invoices but CBAs can only be applied to one invoice.
    # This is to match the method in Zuora::Payment
    with_live_zuora("zuora/get_credit_balance_adjustment_by_id") do
      id = "2c92c0f8748a8d3c01749388f597514a"
      cba = Billing::Zuora::CreditBalanceAdjustment.find(id)

      assert_instance_of Billing::Zuora::CreditBalanceAdjustment, cba
      assert_equal id, cba.id
      assert_equal 1, cba.invoices.count
    end
  end

  test "#invoice_items returns an array of invoice items for the invoice the CBA was applied to" do
    with_live_zuora("zuora/get_credit_balance_adjustment_by_id") do
      id = "2c92c0f8748a8d3c01749388f597514a"
      cba = Billing::Zuora::CreditBalanceAdjustment.find(id)

      assert_instance_of Billing::Zuora::CreditBalanceAdjustment, cba
      assert_equal id, cba.id
    end
  end
end
