# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponExpiringWhenStaleTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @user = create(:user, plan: "small")
      @coupon = create(:coupon, discount: "$5")
    end

    test "expires if stale" do
      @user.redeem_coupon @coupon
      @user.coupon_redemption.update expires_at: GitHub::Billing.now - 1.day
      assert @user.reload.expire_stale_coupon
      assert @user.reload.coupon_redemption.nil?
    end

    test "does not expire active coupon" do
      @user.redeem_coupon @coupon
      refute @user.reload.expire_stale_coupon
      assert @user.reload.coupon_redemption.present?
    end
  end
end
