# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponRecurringBillingWithATrial100OffTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @coupon = create(:coupon, plan: "small", discount: 1)
      @user = create(:user)
    end

    setup do
      @user.redeem_coupon @coupon
    end

    test "doesn't expire the coupon prematurely" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 30.minutes) do
        @user.recurring_charge
        refute @user.coupon_redemption.nil?
      end
    end

    test "can have a stale coupon" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 30.minutes) do
        @user.coupon_redemption.update_attribute :expires_at, GitHub::Billing.now - 1.hour
        assert @user.coupon_redemption.stale?
      end
    end

    test "doesn't change billed_on when disabling an expired trial" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 30.minutes) do
        old_billed_on = @user.billed_on.to_date
        assert @user.payment_method.nil?
        @user.coupon_redemption.update_attribute :expires_at, GitHub::Billing.now - 1.hour
        @user.recurring_charge
        assert_equal old_billed_on, @user.reload.billed_on
      end
    end
  end
end
