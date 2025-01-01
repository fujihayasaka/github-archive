# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponFreeTrialStatesTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @user = create(:user, plan: "small")
    end

    test "#free_trial_locked_to_plan?" do
      coupon = create(:coupon, discount: 12, plan: "small")
      @user.redeem_coupon coupon
      assert_predicate @user, :free_trial_locked_to_plan?

      @user.coupon = create(:coupon, discount: 12)
      refute_predicate @user, :free_trial_locked_to_plan?

      @user.coupon = create(:coupon, discount: 12, plan: "")
      refute_predicate @user, :free_trial_locked_to_plan?
    end
  end
end
