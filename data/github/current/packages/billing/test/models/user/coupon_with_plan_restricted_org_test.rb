# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponWithPlanRestrictedOrgTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @owner     = create(:user)
      @good_org  = create(:organization, admin: @owner, plan: "bronze")
      @bad_org   = create(:organization, plan: "gold")
      @coupon    = create(:coupon, plan: "bronze", discount: 0.5)
      @coupon2   = create(:coupon, plan: "", discount: "$50")
    end

    test "can be redeemed by orgs on that plan" do
      assert @good_org.redeem_coupon(@coupon)
      refute @good_org.redeem_coupon(@coupon2)
    end

    test "can't be redeemed by orgs on other plans" do
      refute @bad_org.redeem_coupon(@coupon)
      assert @bad_org.errors[:coupon].any?
    end

    test "can't be redeemed by orgs for user plans" do
      coupon = create(:coupon, plan: "medium", discount: "100%", duration: 30)

      refute @good_org.redeem_coupon(coupon)
      assert @good_org.errors[:coupon].any?
    end
  end
end
