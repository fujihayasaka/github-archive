# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponCheckingPlanRestrictionsTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @all_coupon  = create :coupon
      @user_coupon = create :coupon, plan: "micro"
      @org_coupon  = create :coupon, plan: "bronze"
    end

    test "#user_coupon?" do
      assert @all_coupon.user_coupon?
      assert @user_coupon.user_coupon?
      assert !@org_coupon.user_coupon?
    end

    test "#org_coupon?" do
      assert @all_coupon.org_coupon?
      assert !@user_coupon.org_coupon?
      assert @org_coupon.org_coupon?
    end

    test "#user_only?" do
      assert !@all_coupon.user_only?
      assert @user_coupon.user_only?
      assert !@org_coupon.user_only?
    end

    test "#org_only?" do
      assert !@all_coupon.org_only?
      assert !@user_coupon.org_only?
      assert @org_coupon.org_only?
    end

    test "all_accounts?" do
      assert @all_coupon.all_accounts?
      assert !@user_coupon.all_accounts?
      assert !@org_coupon.all_accounts?
    end
  end
end
