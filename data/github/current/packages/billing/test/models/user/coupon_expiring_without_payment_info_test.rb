# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponExpiringWithoutPaymentInfoTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @user = create(:user, plan: "small")
    end

    setup do
      ActionMailer::Base.deliveries.clear
    end

    test "moves a user on a free trial but with no private repos from 'small' to 'free'" do
      coupon = create(:coupon, plan: "small", discount: 1.0)

      assert @user.redeem_coupon coupon
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert @user.expire_active_coupon
      end
      assert_equal "free", @user.plan.name
      assert @user.coupon_redemption.nil?
      refute @user.notices_for_dashboard.include?("coupon_will_expire")
      assert_match "Your coupon has expired", ActionMailer::Base.deliveries.first.try(:subject)
    end

    test "moves a user with private repos to 'free'" do
      create(:private_repository, owner: @user) && @user.reload
      coupon = create(:coupon, plan: "small", discount: 1.0)

      assert @user.redeem_coupon coupon
      only = [ApplicationDeliveryJob]
      perform_enqueued_jobs(only: only) do
        assert @user.expire_active_coupon
      end

      assert_equal "free", @user.plan.name
      assert @user.coupon_redemption.nil?
      refute @user.notices_for_dashboard.include?("coupon_will_expire")
      assert_match "Your coupon has expired", ActionMailer::Base.deliveries.first.try(:subject)
    end

    test "disables a user quietly" do
      coupon = create(:coupon, plan: "small", discount: 1.0)

      assert @user.redeem_coupon coupon
      @user.update_attribute(:plan, "gold")

      only = [ApplicationDeliveryJob]
      perform_enqueued_jobs(only: only) do
        @user.expire_active_coupon(quiet: true)
      end

      assert @user.disabled?
      assert @user.coupon_redemption.nil?
      assert_empty ActionMailer::Base.deliveries
    end

    test "disables a user with a legacy plan" do
      coupon = create(:coupon, plan: "small", discount: 1.0)

      assert @user.redeem_coupon coupon
      @user.update_attribute(:plan, "gold")

      only = [ApplicationDeliveryJob]
      perform_enqueued_jobs(only: only) do
        @user.expire_active_coupon
      end
      assert @user.disabled?
      assert @user.coupon_redemption.nil?
      refute @user.notices_for_dashboard.include?("coupon_will_expire")
    end

    test "when billing run happens after coupon expiration, do not add a billing attempt" do
      coupon = create(:coupon, expires_at: 1.day.from_now)
      assert @user.redeem_coupon coupon

      User.any_instance.expects(:save!).raises(ActiveRecord::Rollback)
      Timecop.travel(2.days.from_now) do
        @user.expire_active_coupon
        Billing::DebtHunter.run_start
        @user.reload
        assert_equal 0, @user.billing_attempts
        assert @user.has_an_active_coupon?
      end
    end
  end
end
