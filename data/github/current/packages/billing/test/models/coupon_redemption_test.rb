# typed: true
# frozen_string_literal: true

require "test_helper"

class CouponRedemptionTest < GitHub::BillingTestCase
  setup { ActionMailer::Base.deliveries.clear }

  context "for_coupon scope" do
    test "filters to coupon redemptions using the specified coupon" do
      coupon = create(:coupon, limit: 2)
      redemption1 = create(:coupon_redemption, coupon: coupon)
      redemption2 = create(:coupon_redemption)
      redemption3 = create(:coupon_redemption, coupon: coupon)

      result = CouponRedemption.for_coupon(coupon)

      assert_includes result, redemption1
      refute_includes result, redemption2
      assert_includes result, redemption3
      assert_equal 2, result.size
    end
  end

  context "for_user scope" do
    test "filters to coupon redemptions by the specified user" do
      user = create(:user)
      redemption1 = create(:coupon_redemption, :expired, billable_entity: user)
      redemption2 = create(:coupon_redemption)
      redemption3 = create(:coupon_redemption, billable_entity: user)

      result = CouponRedemption.for_user(user)

      assert_includes result, redemption1
      refute_includes result, redemption2
      assert_includes result, redemption3
      assert_equal 2, result.size
    end
  end

  context ".expire!" do
    test "expires all stale coupons" do
      active_coupon_redemption    = create(:coupon_redemption, expires_at: 2.days.from_now)
      expired_coupon_redemption   = create(:coupon_redemption, expires_at: 2.days.ago)
      stale_coupon_redemption     = create(:coupon_redemption, expires_at: 40.days.ago)
      super_old_coupon_redemption = create(:coupon_redemption, expires_at: 100.days.ago)

      CouponRedemption.expire!

      assert expired_coupon_redemption.reload.expired?
      assert stale_coupon_redemption.reload.expired?
      assert super_old_coupon_redemption.reload.expired?
      refute active_coupon_redemption.reload.expired?
    end

    test "expires all stale coupons even if a user has been deleted" do
      active_coupon_redemption    = create(:coupon_redemption, expires_at: 2.days.from_now)
      expired_coupon_redemption   = create(:coupon_redemption, expires_at: 2.days.ago)
      stale_coupon_redemption     = create(:coupon_redemption, expires_at: 40.days.ago)
      super_old_coupon_redemption = create(:coupon_redemption, expires_at: 100.days.ago)

      User.delete(expired_coupon_redemption.billable_entity_id)

      CouponRedemption.expire!

      assert expired_coupon_redemption.reload.expired?
      assert stale_coupon_redemption.reload.expired?
      assert super_old_coupon_redemption.reload.expired?
      refute active_coupon_redemption.reload.expired?
    end

    test "downgrades to free and notifies users without private repositories" do
      user = create(:user, plan: "pro")
      coupon = create(:coupon, discount: 1.0)
      coupon_redemption = user.redeem_coupon(coupon)
      coupon_redemption.update_attribute(:expires_at, 40.days.ago)

      education_coupon = { education_coupon: coupon.education_coupon? }

      assert_difference "ActionMailer::Base.deliveries.count", 1 do
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "coupon_expired_failure", args: [user, education_coupon]) do
          CouponRedemption.expire!
        end
      end

      refute user.reload.disabled?
      assert_equal GitHub::Plan.free, user.reload.plan

      mail = ActionMailer::Base.deliveries.last
      assert_match /Your coupon has expired/, mail.subject
    end

    test "downgrades to free and notifies users with private repositories" do
      user = create(:user, plan: "pro")
      create(:private_repository, owner: user)
      coupon = create(:coupon, discount: 1.0)
      coupon_redemption = user.redeem_coupon(coupon)
      coupon_redemption.update_attribute(:expires_at, 40.days.ago)
      education_coupon = { education_coupon: coupon.education_coupon? }

      assert_difference "ActionMailer::Base.deliveries.count", 1 do
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "coupon_expired_failure", args: [user, education_coupon]) do
          CouponRedemption.expire!
        end
      end

      refute user.reload.disabled?
      assert_equal GitHub::Plan.free, user.reload.plan

      mail = ActionMailer::Base.deliveries.last
      assert_match /Your coupon has expired/, mail.subject
    end


    test "disables and notifies users with legacy plans" do
      user = create(:paid_user, plan: "gold")
      coupon = create(:coupon, discount: 1.0)
      coupon_redemption = user.redeem_coupon(coupon)
      coupon_redemption.update_attribute(:expires_at, 40.days.ago)
      education_coupon = { education_coupon: coupon.education_coupon? }

      user.update_attribute(:plan, "gold") # make sure it's still set to a legacy plan

      assert user.plan.legacy?

      assert_difference "ActionMailer::Base.deliveries.count", 1 do
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "coupon_expired_failure", args: [user, education_coupon]) do
          CouponRedemption.expire!
        end
      end

      assert user.reload.disabled?

      mail = ActionMailer::Base.deliveries.last
      assert_match /Your coupon has expired/, mail.subject
    end

    test "does not expire coupons before the user has been billed for the time the coupon covers" do
      today = GitHub::Billing.today
      user = create(:user, billed_on: (today - 3.days), plan_duration: "month")
      coupon_redemption = create :coupon_redemption,
        billable_entity: user,
        expires_at: today - 2.days

      CouponRedemption.expire!

      refute coupon_redemption.reload.expired?
    end
  end

  context "#expired_since_last_billing?" do
    test "true if expired after previous billing cycle" do
      today = GitHub::Billing.today
      user = create(:user, billed_on: (today + 15.days), plan_duration: "month")
      coupon_redemption = create :coupon_redemption,
        billable_entity: user,
        expires_at: today - 2.days

      assert coupon_redemption.expired_since_last_billing?
    end

    test "false if expired before previous billing cycle" do
      today = GitHub::Billing.today
      user = create(:user, billed_on: (today + 15.days), plan_duration: "month")
      coupon_redemption = create :coupon_redemption,
        billable_entity: user,
        expires_at: today - 52.days

      refute coupon_redemption.expired_since_last_billing?
    end
  end

  context "#expires_before_billing_date?" do
    test "true if the expiration date is before the billed_on date" do
      # Freeze time at 6 AM UTC so that in Pacific time, it's still the previous day
      # This ensures that the test will only pass if the comparison is made using Pacific time
      Timecop.freeze(2022, 11, 1, 6) do
        billed_on = GitHub::Billing.today
        expires_at = Time.now.utc - 1.day

        user = create(:user, billed_on: billed_on, plan_duration: "month")
        coupon_redemption = create(:coupon_redemption, billable_entity: user, expires_at: expires_at)

        assert coupon_redemption.expires_before_billing_date?
      end
    end

    test "true if billed_on is nil and the expiration date < today" do
      # Freeze time at 6 AM UTC so that in Pacific time, it's still the previous day
      # This ensures that the test will only pass if the comparison is made using Pacific time
      Timecop.freeze(2022, 11, 1, 6) do
        billed_on = nil
        expires_at = Time.now.utc - 1.day

        user = create(:user, billed_on: billed_on, plan_duration: "month")
        coupon_redemption = create(:coupon_redemption, billable_entity: user, expires_at: expires_at)

        assert coupon_redemption.expires_before_billing_date?
      end
    end

    test "false if the expiration date is the billed_on date" do
      # Freeze time at 8 AM UTC so that the date is the same in UTC or Pacific time
      Timecop.freeze(2022, 11, 1, 8) do
        billed_on = GitHub::Billing.today
        expires_at = Time.now.utc

        user = create(:user, billed_on: billed_on, plan_duration: "month")
        coupon_redemption = create(:coupon_redemption, billable_entity: user, expires_at: expires_at)

        refute coupon_redemption.expires_before_billing_date?
      end
    end

    test "false if the expiration date is after billed_on date" do
      # Freeze time at 8 AM UTC so that the date is the same in UTC or Pacific time
      Timecop.freeze(2022, 11, 1, 8) do
        billed_on = GitHub::Billing.today
        expires_at = Time.now.utc + 1.day

        user = create(:user, billed_on: billed_on, plan_duration: "month")
        coupon_redemption = create(:coupon_redemption, billable_entity: user, expires_at: expires_at)

        refute coupon_redemption.expires_before_billing_date?
      end
    end
  end

  test "always returns expires_at in Pacfic timezone" do
    coupon_redemption = create :coupon_redemption
    coupon_redemption.expires_at = Time.current # UTC

    assert_equal GitHub::Billing.timezone, coupon_redemption.expires_at.time_zone
  end

  context ".expiring_in_two_weeks" do
    test "returns coupons expiring two weeks from now" do
      Timecop.freeze(2017, 2, 1, 12, 34, 56) do
        expiring_in_one_week = create(:coupon_redemption, expires_at: 1.week.from_now)
        expiring_in_two_weeks = create(:coupon_redemption, expires_at: 2.weeks.from_now)

        assert_equal [expiring_in_two_weeks], CouponRedemption.expiring_in_two_weeks
      end
    end

    test "takes an optional from argument" do
      Timecop.freeze(2017, 2, 1, 12, 34, 56) do
        expiring_in_one_week = create(:coupon_redemption, expires_at: 8.days.from_now)
        expiring_in_two_weeks = create(:coupon_redemption, expires_at: 2.weeks.from_now)

        assert_equal [expiring_in_one_week], CouponRedemption.expiring_in_two_weeks(from: 6.days.ago)
      end
    end
  end

  context ".expiring_in_one_week" do
    test "returns coupons expiring one week from now" do
      Timecop.freeze(2017, 2, 1, 12, 34, 56) do
        expiring_in_one_week = create(:coupon_redemption, expires_at: 1.week.from_now)
        expiring_in_two_weeks = create(:coupon_redemption, expires_at: 2.weeks.from_now)

        assert_equal [expiring_in_one_week], CouponRedemption.expiring_in_one_week
      end
    end

    test "takes an optional from argument" do
      Timecop.freeze(2017, 2, 1, 12, 34, 56) do
        expiring_in_one_week = create(:coupon_redemption, expires_at: 7.days.from_now)
        expiring_in_two_weeks = create(:coupon_redemption, expires_at: 13.days.from_now)

        assert_equal [expiring_in_two_weeks], CouponRedemption.expiring_in_one_week(from: 6.days.from_now)
      end
    end
  end

  context "#expire!" do
    test "instruments and updates without sync" do
      active_coupon_redemption    = create(:coupon_redemption, expires_at: 2.days.from_now)

      events = subscribe("coupon_redemption.expire")
      active_coupon_redemption.expire!

      expected_payload = {
        id: active_coupon_redemption.id,
        billable_entity_id: active_coupon_redemption.billable_entity_id,
        billable_entity_type: active_coupon_redemption.billable_entity_type,
        coupon_id: active_coupon_redemption.coupon_id,
      }
      assert_equal 1, events.size

      assert_equal expected_payload, events.first.payload
      assert active_coupon_redemption.reload.expired?
    end
  end

  context "after_commit synchronize_plan_subscription" do
    test "enqueues SynchronizePlanSubscriptionJob once a user with an external subscription redeems a coupon" do
      user = create(:user, :zuora, plan: "pro")
      plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
      assert user.external_subscription?
      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        create(:coupon_redemption, :expired, billable_entity: user)
      end
    end

    test "enqueues SynchronizePlanSubscriptionJob once a user without an external subscription redeems a coupon" do
      user = create(:user)
      refute user.external_subscription?
      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        create(:coupon_redemption, :expired, billable_entity: user)
      end
    end
  end
end
