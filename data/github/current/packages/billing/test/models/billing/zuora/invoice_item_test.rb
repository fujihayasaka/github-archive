# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::InvoiceItemTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  fixtures do
    @sub_item = create(:billing_subscription_item)
  end

  setup do
    @invoice_item_response = {
      "chargeAmount" => 162.4,
      "id" => "2c92c0fa65f203fe0165f74569e828ac",
      "quantity" => 8,
      "unitOfMeasure" => "Seats",
      "unitPrice" => 180.0,
      "chargeName" => "GitHub Business Plan - Month",
      "subscriptionName" => "A-S00004635",
      "productRatePlanChargeId" => "2c92c0fa65f203fe0165f74569e99ab"
    }
    @invoice_item = Billing::Zuora::InvoiceItem.new(@invoice_item_response)
  end

  context "attributes" do
    test "retrieves undecorated values from invoice item response" do
      assert_equal @invoice_item_response["id"], @invoice_item.id
      assert_equal @invoice_item_response["chargeName"], @invoice_item.charge_name
      assert_equal @invoice_item_response["quantity"], @invoice_item.quantity
      assert_equal @invoice_item_response["unitOfMeasure"], @invoice_item.unit
      assert_equal @invoice_item_response["subscriptionName"], @invoice_item.subscription_number
      assert_equal @invoice_item_response["productRatePlanChargeId"], @invoice_item.product_rate_plan_charge_id
    end

    test "retrieves monetary values as Billing::Money" do
      assert_equal Billing::Money.new(@invoice_item_response["chargeAmount"] * 100), @invoice_item.charge_amount
      assert_equal Billing::Money.new(@invoice_item_response["unitPrice"] * 100), @invoice_item.unit_price
    end
  end

  context "#==" do
    test "equal if same raw Zuora response" do
      item1 = Billing::Zuora::InvoiceItem.new(@invoice_item_response)
      item2 = Billing::Zuora::InvoiceItem.new(@invoice_item_response)

      assert_equal item1, item1
      assert_equal item1, item2
    end

    test "unequal if different raw Zuora response" do
      different_item_response = @invoice_item_response.merge({ "quantity" => 0 })
      item1 = Billing::Zuora::InvoiceItem.new(@invoice_item_response)
      item2 = Billing::Zuora::InvoiceItem.new(different_item_response)

      refute_equal item1, item2
    end

    test "unequal if different object" do
      item1 = Billing::Zuora::InvoiceItem.new(@invoice_item_response)
      item2 = :foo

      refute_equal item1, item2
    end
  end

  context "#as_subscribable_invoice_item" do
    test "supports only including a subscribable" do
      subscribable_invoice_item = @invoice_item.as_subscribable_invoice_item(subscribable: @sub_item.subscribable)

      assert_equal @sub_item.subscribable, subscribable_invoice_item.subscribable
      assert_nil subscribable_invoice_item.subscription_item
    end

    test "support also including a subscription item" do
      subscribable_invoice_item = @invoice_item.as_subscribable_invoice_item(
        subscribable: @sub_item.subscribable,
        subscription_item: @sub_item
      )

      assert_equal @sub_item.subscribable, subscribable_invoice_item.subscribable
      assert_equal @sub_item, subscribable_invoice_item.subscription_item
    end
  end
end
