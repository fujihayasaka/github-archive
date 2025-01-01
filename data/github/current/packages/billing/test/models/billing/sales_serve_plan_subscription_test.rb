# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingSalesServePlanSubscriptionTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
    @azure_business = create(:business, :with_azure_subscription)
  end

  context "#zuora_rate_plan_charge_number" do
    test "returns nil when the product rate plan charge ID doesn't match" do
      plan_subscription = create(:billing_sales_serve_plan_subscription)

      assert_nil plan_subscription.zuora_rate_plan_charge_number(
        product_rate_plan_charge_id: "mismatch",
      )
    end

    test "returns the rate plan charge number if there's a product rate plan charge ID match" do
      rate_plan_charges = {
        "matching-id" => { number: "123" },
      }
      plan_subscription = create(:billing_sales_serve_plan_subscription, zuora_rate_plan_charges: rate_plan_charges)

      assert_equal "123", plan_subscription.zuora_rate_plan_charge_number(
        product_rate_plan_charge_id: "matching-id",
      )
    end
  end

  context "education_bundle?" do
    test "returns false when not on an education bundle" do
      plan_subscription = build :billing_sales_serve_plan_subscription

      refute plan_subscription.education_bundle?
    end

    test "returns true when on an education bundle" do
      plan_subscription = build :billing_sales_serve_plan_subscription,
        education_bundle: :essential

      assert plan_subscription.education_bundle?
    end
  end

  context "validations zuora ids" do
    test "requires ids for zuora customers with charges" do
      plan_sub = build :billing_sales_serve_plan_subscription,
        customer: @business.customer,
        zuora_rate_plan_charges: { charge_one: 4242 },
        zuora_subscription_id: nil,
        zuora_subscription_number: nil

      plan_sub.save

      error_columns = plan_sub.errors.map(&:attribute)
      assert_includes error_columns, :zuora_subscription_id
      assert_includes error_columns, :zuora_subscription_number
    end

    test "doesn't require ids for subscription without charges" do
      plan_sub = build :billing_sales_serve_plan_subscription,
        customer: @business.customer,
        zuora_rate_plan_charges: {},
        zuora_subscription_id: nil,
        zuora_subscription_number: nil

      assert plan_sub.save

      assert_empty plan_sub.errors
    end

    test "doesn't require ids for customers billed through azure" do
      plan_sub = build :billing_sales_serve_plan_subscription,
        customer: @azure_business.customer,
        zuora_subscription_id: nil,
        zuora_subscription_number: nil

      assert plan_sub.save

      assert_empty plan_sub.errors
    end
  end

  context "#update" do
    test "touches customer on updates" do
      plan_sub = create :billing_sales_serve_plan_subscription, customer: @business.customer

      travel_to 1.hour.from_now do
        assert_changes(-> { @business.customer.updated_at }) do
          plan_sub.update!(zuora_subscription_number: "A1234")
          plan_sub.reload
        end
      end
    end
  end
end if GitHub.billing_enabled?
