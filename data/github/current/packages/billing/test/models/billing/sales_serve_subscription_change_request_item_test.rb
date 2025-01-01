# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SalesServeSubscriptionChangeRequestItemTest < GitHub::TestCase
  context "validations" do
    test "pass for default values" do
      item = build(:sales_serve_subscription_change_request_item)

      assert_predicate(item, :valid?)
    end

    test "status is required" do
      item = build(:sales_serve_subscription_change_request_item, status: nil)

      refute_predicate(item, :valid?)
      assert_equal ["can't be blank"], item.errors[:status]
    end

    test "product_rate_plan_charge_id is required" do
      item = build(:sales_serve_subscription_change_request_item, product_rate_plan_charge_id: nil)

      refute_predicate(item, :valid?)
      assert_equal ["can't be blank"], item.errors[:product_rate_plan_charge_id]
    end

    test "change_type is required" do
      item = build(:sales_serve_subscription_change_request_item, change_type: nil)

      refute_predicate(item, :valid?)
      assert_equal ["can't be blank"], item.errors[:change_type]
    end

    test "start_date is required" do
      item = build(:sales_serve_subscription_change_request_item, start_date: nil)

      refute_predicate(item, :valid?)
      assert_equal ["can't be blank"], item.errors[:start_date]
    end

    test "end_date is required" do
      item = build(:sales_serve_subscription_change_request_item, end_date: nil)

      refute_predicate(item, :valid?)
      assert_equal ["can't be blank"], item.errors[:end_date]
    end

    test "change_request is required" do
      item = build(:sales_serve_subscription_change_request_item, change_request: nil)

      refute_predicate(item, :valid?)
      assert_equal ["must exist"], item.errors[:change_request]
    end
  end
end
