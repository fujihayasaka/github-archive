# typed: true
# frozen_string_literal: true

require "test_helper"

class ZuoraDependencyForCouponTest < GitHub::TestCase
  context "#sync_to_zuora" do
    test "creates percentage-off coupon in zuora if one doesn't exist" do
      VCR.use_cassette("zuora/github_percentage_discount_product") do
        coupon = create(:coupon, discount: 0.5)
        # Create plans for the coupon to apply to
        plan = GitHub::Plan.pro
        plan.sync_to_zuora
        mp = create(:marketplace_listing_plan, :per_unit)
        mp.sync_to_zuora

        assert_difference "Billing::ProductUUID.count", 2 do
          assert coupon.sync_to_zuora
        end

        User::BillingDependency::PLAN_DURATIONS.each do |cycle|
          uuid = Billing::ProductUUID.find_by!(product_type: "github.coupon", product_key: "percentage", billing_cycle: cycle)
          assert uuid.zuora_product_id
          assert uuid.zuora_product_rate_plan_id
          assert uuid.zuora_product_rate_plan_charge_ids[:percentage_discount]
          refute uuid.zuora_product_rate_plan_charge_ids[:fixed_discount]
        end
      end
    end

    test "creates fixed-amount coupon in zuora if one doesn't exist" do
      VCR.use_cassette("zuora/github_fixed_discount_product") do
        coupon = create(:coupon, discount: 7)
        # Create plans for the coupon to apply to
        plan = GitHub::Plan.pro
        plan.sync_to_zuora
        mp = create(:marketplace_listing_plan, :per_unit)
        mp.sync_to_zuora

        assert_difference "Billing::ProductUUID.count", 2 do
          assert coupon.sync_to_zuora
        end

        User::BillingDependency::PLAN_DURATIONS.each do |cycle|
          uuid = Billing::ProductUUID.find_by!(product_type: "github.coupon", product_key: "fixed_amount", billing_cycle: cycle)
          assert uuid.zuora_product_id
          assert uuid.zuora_product_rate_plan_id
          assert uuid.zuora_product_rate_plan_charge_ids[:fixed_discount]
          refute uuid.zuora_product_rate_plan_charge_ids[:percentage_discount]
        end
      end
    end
  end

  context "#zuora_id" do
    test "grabs the zuora id from the product uuid record" do
      create(
        :billing_product_uuid,
        product_type: "github.coupon",
        product_key: "percentage",
        billing_cycle: "month",
        zuora_product_rate_plan_id: "123abc",
      )

      coupon = create(:coupon, discount: 0.4)

      assert_equal "123abc", coupon.zuora_id(cycle: User::BillingDependency::MONTHLY_PLAN)
    end
  end
end if GitHub.billing_enabled?
