# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponRemainingDiscountCalculatesUnusedDiscountAmountTest < GitHub::TestCase
    include GitHub::BillingTest

    test "returns $0 for a percent discount" do
      user = create :user, plan: "medium"
      user.redeem_coupon create(:coupon, discount: 0.8)
      assert_money 0, user.remaining_discount
    end

    test "returns partial amount if user has applied coupon to a smaller plan" do
      discount = 30
      user = create :user, plan: "pro"
      user.redeem_coupon create(:coupon, discount: discount)
      assert_money (discount - user.plan.cost) * 100, user.remaining_discount
    end

    test "knows about data packs" do
      discount = 40
      user = create :user, plan: "pro"
      create :asset_status, owner: user, asset_packs: 2
      user.redeem_coupon create(:coupon, discount: discount)
      plan_cost = user.plan.cost
      data_pack_cost = 2 * Asset::Status.data_pack_unit_price.dollars

      assert_money (discount - plan_cost - data_pack_cost) * 100, user.remaining_discount
    end

    test "returns $0 if user has a coupon that doesn't cover entire plan" do
      user = create :user, plan: "pro"
      create :asset_status, owner: user, asset_packs: 3
      user.redeem_coupon create(:coupon, discount: 15)

      assert_money 0, user.remaining_discount
    end

    test "returns $0 for plan-specific coupons" do
      user = create :user, plan: "medium"
      user.redeem_coupon create(:coupon, discount: 100, plan: "gold")
      assert_money 0, user.remaining_discount
    end

    test "calculates correct discount for yearly plans" do
      discount = 100
      user = create(:user, plan: "pro", plan_duration: "year")
      coupon = create(:coupon, discount: discount)
      user.redeem_coupon(coupon)

      plan_cost = user.plan.cost
      assert_money (discount - plan_cost) * 100, user.remaining_discount
    end
  end
end
