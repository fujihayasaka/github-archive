# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SalesServeSubscriptionChangeRequestTest < GitHub::TestCase
  include HydroTestHelpers

  context "validations" do
    test "pass for default values" do
      change_request = build(:sales_serve_subscription_change_request)

      assert_predicate(change_request, :valid?)
    end

    test "request_uuid is required" do
      change_request = build(:sales_serve_subscription_change_request, request_uuid: nil)

      refute_predicate(change_request, :valid?)
      assert_equal ["can't be blank"], change_request.errors[:request_uuid]
    end

    test "request_uuid is generated" do
      change_request = build(:sales_serve_subscription_change_request)

      assert_predicate(change_request, :valid?)
      refute_nil change_request.request_uuid
    end

    test "request_uuid is not generated if it is already set" do
      change_request = build(:sales_serve_subscription_change_request, request_uuid: "1234")

      assert_predicate(change_request, :valid?)
      assert_equal "1234", change_request.request_uuid
    end

    test "request_uuid is not generated if it is already set and read from db" do
      change_request = build(:sales_serve_subscription_change_request)

      assert_no_changes("change_request.request_uuid") do
        change_request.save!
      end
    end

    test "request_uuid is unique" do
      change_request = create(:sales_serve_subscription_change_request)
      another_change_request = build(:sales_serve_subscription_change_request, request_uuid: change_request.request_uuid)

      refute_predicate(another_change_request, :valid?)
      assert_equal ["has already been taken"], another_change_request.errors[:request_uuid]
    end

    test "zuora_subscription_id is required" do
      change_request = build(:sales_serve_subscription_change_request, zuora_subscription_id: nil)

      refute_predicate(change_request, :valid?)
      assert_equal ["can't be blank"], change_request.errors[:zuora_subscription_id]
    end

    test "customer is required" do
      change_request = build(:sales_serve_subscription_change_request, customer: nil)

      refute_predicate(change_request, :valid?)
      assert_equal ["can't be blank"], change_request.errors[:customer_id]
    end

    test "items are not required" do
      change_request = build(:sales_serve_subscription_change_request)

      assert_predicate(change_request, :valid?)
    end

    test "items should be valid" do
      change_request = build(:sales_serve_subscription_change_request)
      change_request.items.build

      refute_predicate(change_request, :valid?)
      assert_equal ["can't be blank"], change_request.errors["items.change_type"]

      change_request.items.clear
      change_request.items << build(:sales_serve_subscription_change_request_item, change_request: change_request)

      assert_predicate(change_request, :valid?)
    end

    test "items are destroyed when the change request is destroyed" do
      change_request = create(:sales_serve_subscription_change_request_with_items)

      assert_difference("Billing::SalesServeSubscriptionChangeRequestItem.count", -2) do
        change_request.destroy
      end
    end
  end

  context "#send_to_salesforce" do
    test "publishes the hydro event" do
      request = create(:sales_serve_subscription_change_request)
      product_rate_plan_charge_id = SecureRandom.hex(16)
      price = 100.0
      update_quantity = 5
      renewal_quantity = 10
      update_start_date = 1.month.from_now.change(nsec: 0)
      update_end_date = 2.months.from_now.change(nsec: 0)
      renewal_start_date = 2.months.from_now.change(nsec: 0)
      renewal_end_date = (2.months + 1.year).from_now.change(nsec: 0)
      request.items << create(:sales_serve_subscription_change_request_item, product_rate_plan_charge_id:, price:, quantity: update_quantity, change_type: :update, start_date: update_start_date, end_date: update_end_date)
      request.items << create(:sales_serve_subscription_change_request_item, product_rate_plan_charge_id:, price:, quantity: renewal_quantity, change_type: :renewal, start_date: renewal_start_date, end_date: renewal_end_date)
      result = request.send_to_salesforce

      assert result
      assert_hydro_published({
        request_id: request.request_uuid,
        zuora_subscription_id: request.zuora_subscription_id,
        product: [
          {
            product_rate_plan_charge_id: product_rate_plan_charge_id,
            quantity: update_quantity,
            price: price,
            start_date: update_start_date,
            end_date: update_end_date,
            type: "update",
          },
          {
            product_rate_plan_charge_id: product_rate_plan_charge_id,
            quantity: renewal_quantity,
            price: price,
            start_date: renewal_start_date,
            end_date: renewal_end_date,
            type: "renewal",
          }
        ]
      }, schema: "github.billing.v0.SalesforceSubscriptionRequest")
    end
  end if GitHub.hydro_enabled?
end
