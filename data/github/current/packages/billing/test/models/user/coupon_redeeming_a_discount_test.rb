# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponRedeemingADiscountTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @coupon = create(:coupon, discount: "$12")
    end

    test "upgrades your plan if you're on free" do
      user = create(:user)
      user.redeem_coupon @coupon
      assert_equal "pro", user.plan.to_s
    end

    test "upgrades your plan to the best guess if you're on free" do
      user   = create(:user)
      coupon = create(:coupon, discount: "$10")
      user.redeem_coupon coupon
      assert_equal "pro", user.plan.to_s
    end

    test "upgrades your plan if you can afford a bigger one" do
      user = create :user, plan: "micro"
      user.redeem_coupon @coupon
      assert_equal "pro", user.plan.to_s
    end

    test "doesn't upgrade your plan if you're on the optimal plan" do
      user = create :user, plan: "small"
      user.redeem_coupon @coupon
      assert_equal "pro", user.plan.to_s
    end

    test "doesn't upgrade your plan if you're on a bigger plan" do
      user = create :user, plan: "medium"
      user.redeem_coupon @coupon
      assert_equal "pro", user.plan.to_s
    end

    test "deactivates trial when on cloud trial to prevent later downgrade" do
      org = create :free_organization
      Billing::EnterpriseCloudTrial.new(org).create
      enterprise_coupon = create :coupon, plan: GitHub::Plan.business_plus, discount: 1.0

      org.redeem_coupon enterprise_coupon
      assert_equal org.reload.plan, GitHub::Plan.business_plus
      refute org.on_enterprise_cloud_trial?
    end

    test "doesn't deactivate trial for non-enterprise coupons" do
      org = create :free_organization
      Billing::EnterpriseCloudTrial.new(org).create
      coupon = create :coupon, discount: 0.8

      org.redeem_coupon coupon
      assert org.reload.on_enterprise_cloud_trial?
    end

    test "sets seat count to default_seats when deactivating a trial to avoid over-billing" do
      org = create :free_organization
      Billing::EnterpriseCloudTrial.new(org).create
      enterprise_coupon = create :coupon, plan: GitHub::Plan.business_plus, discount: 1.0

      assert_equal org.reload.seats, 50
      org.redeem_coupon enterprise_coupon
      assert_equal org.reload.seats, 1
    end
  end
end
