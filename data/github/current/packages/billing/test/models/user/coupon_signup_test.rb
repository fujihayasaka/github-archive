# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponSignupTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @coupon = create(:coupon, discount: 0.5)
    end

    setup do
      @user = create(:user, plan: "small")
    end

    test "works if the coupon is valid" do
      @user.coupon = @coupon.code
      assert @user.save

      plan_cost = @user.reload.plan.cost
      assert_equal plan_cost - (plan_cost * @coupon.discount), @user.payment_amount
    end

    test "fails if the coupon is invalid" do
      @user.coupon = "make-believe"
      refute @user.save
      assert @user.errors[:coupon].any?
    end

    test "works for 100% discounts" do
      coupon = create(:coupon, discount: "100%", plan: "small")
      @user.coupon = coupon.code
      assert @user.save
      assert @user.save
      assert_equal 0, @user.payment_amount
    end
  end
end
