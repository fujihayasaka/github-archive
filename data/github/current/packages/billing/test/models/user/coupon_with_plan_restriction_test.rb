# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponWithPlanRestrictionTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @good_user = create(:user, plan: "small")
      @bad_user  = create(:user, plan: "medium")
      @coupon    = create(:coupon, plan: "small", discount: 0.5)
      @coupon2   = create(:coupon, plan: "", discount: "$12")
    end

    test "can be redeemed by users on that plan" do
      assert @good_user.redeem_coupon(@coupon)
      refute @good_user.redeem_coupon(@coupon2)
    end

    test "can't be redeemed by users on other plans" do
      refute @bad_user.redeem_coupon(@coupon)
      assert @bad_user.errors[:coupon].any?
    end

    test "can't be redeemed by users for org plans" do
      coupon = create(:coupon, plan: "bronze", discount: "100%", duration: 30)
      user   = create(:user)

      refute user.redeem_coupon(coupon)
      assert user.errors[:coupon].any?
    end

    test "can't be redeemed if there are already too many repos" do
      coupon = create(:coupon, plan: "micro", discount: 1)
      user = create(:user, plan: "small")
      6.times do
        create(:private_repository, owner: user)
      end
      user.reload

      refute user.redeem_coupon(coupon)
      assert user.errors[:coupon].any?
    end
  end
end
