# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponRedeemingWithAnExistingPlanTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @user   = create(:user, plan: "small", billed_on: GitHub::Billing.today + 25.days)
      @coupon = create(:coupon, code: "yahoo-devcamp",
                            discount: 0.5,
                            limit: 50)
      assert_nil @user.coupon
      @user.redeem_coupon @coupon.code
      assert_equal @coupon, @user.coupon
    end

    test "sets expiration properly" do
      assert_operator @user.coupon_redemption.expires_at, :>=, GitHub::Billing.now + 29.days
      assert_operator @user.billed_on, :>=, GitHub::Billing.today + 25.days
    end
  end
end
