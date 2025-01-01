# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponOrgCreationTest < GitHub::TestCase
    include GitHub::BillingTest

    test "works if the coupon is valid" do
      coupon = create(:coupon, discount: 0.5)
      org = create(:organization, plan: "bronze")
      org.coupon = coupon.code
      assert org.save
      assert_equal 12.5, org.payment_amount
    end

    test "fails if the coupon is invalid" do
      org = create(:organization, plan: "bronze")
      org.coupon = "make-believe"
      refute org.save
      assert org.errors[:coupon].any?
    end

    test "don't change org plan for partial discounts" do
      org = create(:organization, plan: "free")
      coupon = create(:coupon, discount: "50%")
      org.coupon = coupon.code
      assert org.save, org.errors.full_messages.inspect

      assert_equal GitHub::Plan.free, org.plan
      assert_equal 0, org.seats
      assert_equal 0, org.payment_amount
    end

    test "puts a new org on the right plan for 100% discounts" do
      org = create(:organization, plan: "free")
      coupon = create(:coupon, discount: "100%")
      org.coupon = coupon.code
      assert org.save, org.errors.full_messages.inspect
      assert_equal GitHub::Plan.business, org.plan

      assert_equal 1, org.seats
      assert_equal 0, org.payment_amount
    end
  end
end
