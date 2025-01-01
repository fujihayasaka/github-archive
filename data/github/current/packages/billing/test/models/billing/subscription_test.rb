# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SubscriptionTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  fixtures do
    @owner = create(:user)
    @org = create(:organization,
      plan: "business",
      admin: @owner,
      seats: 5,
      billed_on: GitHub::Billing.today + 1.year,
      plan_duration: "year")
    @monthly_org = create(:organization, plan_duration: "month")
  end

  sig { returns(Date) }
  def today
    GitHub::Billing.today
  end

  context ".new" do
    test "defaults to subscription starting today for 1 month" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 1, 1)) do
        today = GitHub::Billing.today
        subscription = Billing::Subscription.new

        assert_equal 1, subscription.duration_in_months
        assert_equal 31, subscription.duration_in_days
        assert_equal today, subscription.service_starts_on
        assert_equal Date.new(2015, 1, 31), subscription.service_ends_on
        assert_equal 30, subscription.service_days_remaining
        assert_equal (30 / 31.0), subscription.service_percent_remaining
      end
    end

    test "providing both start and end" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        subscription = Billing::Subscription.new(starts: today, ends: today + 13.days)
        assert_equal 1, subscription.duration_in_months
        assert_equal 14, subscription.duration_in_days
        assert_equal Date.new(2015, 6, 18), subscription.service_starts_on
        assert_equal Date.new(2015, 7, 1), subscription.service_ends_on
        assert_equal 13, subscription.service_days_remaining
      end
    end

    test "providing just start" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        subscription = Billing::Subscription.new(starts: Date.new(2015, 6, 8))
        assert_equal 1, subscription.duration_in_months
        assert_equal Date.new(2015, 6, 8), subscription.service_starts_on
        assert_equal Date.new(2015, 7, 7), subscription.service_ends_on
        assert_equal 19, subscription.service_days_remaining
      end
    end

    test "providing start and duration" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        subscription = Billing::Subscription.new(starts: today, duration_in_months: 2)
        assert_equal 2, subscription.duration_in_months
        assert_equal today, subscription.service_starts_on
        assert_equal Date.new(2015, 8, 17), subscription.service_ends_on
        # Days in June + Days in July - 1 day (service ends day before bill date)
        assert_equal 30 + 31 - 1, subscription.service_days_remaining
      end
    end

    test "providing just end" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        subscription = Billing::Subscription.new(ends: Date.new(2015, 7, 1))
        assert_equal 1, subscription.duration_in_months
        assert_equal Date.new(2015, 6, 2), subscription.service_starts_on
        assert_equal Date.new(2015, 7, 1), subscription.service_ends_on
        assert_equal 13, subscription.service_days_remaining
      end
    end

    test "providing end and duration" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        subscription = Billing::Subscription.new(ends: Date.new(2015, 6, 28), duration_in_months: 2)
        assert_equal 2, subscription.duration_in_months
        assert_equal Date.new(2015, 4, 29), subscription.service_starts_on
        assert_equal Date.new(2015, 6, 28), subscription.service_ends_on
        assert_equal 10, subscription.service_days_remaining
      end
    end

    test "when today is past the subscription start date" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        subscription = Billing::Subscription.new \
          starts: Date.new(2015, 6, 8),
          ends: Date.new(2015, 6, 28)

        assert_equal 21, subscription.duration_in_days
        assert_equal 10, subscription.service_days_remaining
        assert_equal (10.0 / 21.0), subscription.service_percent_remaining
      end
    end

    test "providing end on the 1st of a month that follows a < 31-day month" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 1, 29)) do
        service_ends_on = Date.new(2015, 2, 28)
        subscription = Billing::Subscription.new(ends: service_ends_on, duration_in_months: 1)
        assert_equal Date.new(2015, 2, 1), subscription.service_starts_on
        assert_equal Date.new(2015, 2, 28), subscription.service_ends_on
        assert_equal 30, subscription.service_days_remaining
        assert_equal 1, subscription.service_percent_remaining
      end
    end

    test "providing an active_on prorates the subscription" do
      Timecop.freeze(GitHub::Billing.timezone.local(2017, 10, 22)) do
        subscription = Billing::Subscription.new(active_on: Date.new(2017, 11, 05))

        assert_equal 1, subscription.duration_in_months
        assert_equal Date.new(2017, 10, 22), subscription.service_starts_on
        assert_equal Date.new(2017, 11, 21), subscription.service_ends_on
        # 16 days from active_on to end date
        assert_equal 16, subscription.service_days_remaining
      end
    end
  end

  context ".for_account" do
    test "account required" do
      assert_raises ArgumentError do
        Billing::Subscription.for_account(nil)
      end
    end

    test "uses billed_on from account" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        user = create(:user, billed_on: Date.new(2015, 6, 28))
        assert_equal user.billed_on, user.subscription.service_next_bills_on
        assert_equal user.billed_on, user.subscription.service_ends_on + 1.day
        assert_equal 9, user.subscription.service_days_remaining
      end
    end

    test "uses account plan_duration if billed_on is nil" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        user = create(:user, billed_on: nil)
        assert_equal today, user.subscription.service_starts_on
        assert_equal Date.new(2015, 7, 17), user.subscription.service_ends_on
        assert_equal 30 - 1, user.subscription.service_days_remaining
      end
    end

    test "uses passed plan_duration if billed_on is nil" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        user = create(:user, billed_on: nil)
        subscription = Billing::Subscription.for_account(user, duration_in_months: 2)
        assert_equal Date.new(2015, 6, 18), subscription.service_starts_on
        assert_equal Date.new(2015, 8, 17), subscription.service_ends_on
        # Days in June + Days in July - 1 day (service ends day before bill date)
        assert_equal 30 + 31 - 1, subscription.service_days_remaining
      end
    end
  end

  context ".based_on_subscription" do
    test "subscription required" do
      assert_raises ArgumentError do
        Billing::Subscription.based_on_subscription(nil, seats: 0, coupon_discount: 0)
      end
    end

    test "preserves subscription items" do
      listing_plan = create :marketplace_listing_plan,
        :verified_listing,
        monthly_price_in_cents: 10_00
      item = Billing::SubscriptionItem.new \
        subscribable: listing_plan,
        quantity: 1

      old_subscription = Billing::Subscription.new \
        plan: GitHub::Plan.business,
        subscription_items: [item]

      new_subscription = Billing::Subscription.based_on_subscription \
          old_subscription,
          seats: 1,
          coupon_discount: 0

      assert_equal old_subscription.discounted_price, new_subscription.discounted_price
    end

    test "allows setting new values" do
      old_subscription = Billing::Subscription.new(plan: GitHub::Plan.business, seats: 2, data_packs: 0)
      subscription = Billing::Subscription.based_on_subscription \
        old_subscription,
        seats: 10,
        coupon_discount: 0

      assert_equal 10, subscription.seats
    end
  end

  context "#next_bill_date_after" do
    test "returns the next time the user will be billed, after the given date" do
      user = create(:user, billed_on: Date.new(2017, 10, 10))

      date = Date.new(2017, 11, 1)
      next_bill_date_after_date = Date.new(2017, 11, 10)
      assert_equal user.billed_on, user.subscription.service_next_bills_on
      assert_equal next_bill_date_after_date, user.subscription.next_bill_date_after(date: date)

      yearly_user = create :user,
        plan_duration: "year",
        billed_on: Date.new(2017, 10, 10)

      date = Date.new(2017, 11, 1)
      next_bill_date_after_date = Date.new(2018, 10, 10)
      assert_equal yearly_user.billed_on, yearly_user.subscription.service_next_bills_on
      assert_equal next_bill_date_after_date, yearly_user.subscription.next_bill_date_after(date: date)
    end

    test "returns next_billed_on if date is before next_billed_on" do
      user = create(:user, billed_on: Date.new(2017, 10, 10))

      date = Date.new(2017, 10, 3)
      assert_equal user.billed_on, user.subscription.service_next_bills_on
      assert_equal user.billed_on, user.subscription.next_bill_date_after(date: date)
    end

  end

  context "#service_days_remaining" do
    test "10 days from now" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        @org.billed_on = today + 10.days
        assert_equal 9, @org.subscription.service_days_remaining
      end
    end

    test "one day before billed_on" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        @org.billed_on = today + 1.day
        assert_equal 0, @org.subscription.service_days_remaining
      end
    end

    test "on billed_on" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        @org.billed_on = today
        assert_equal 0, @org.subscription.service_days_remaining
      end
    end

    test "in the past" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 6, 18)) do
        @org.billed_on = today - 1.day
        assert_equal 0, @org.subscription.service_days_remaining
      end
    end
  end

  context "#discounted_price" do
    test "includes coupon discount" do
      @monthly_org.update(plan: "business", seats: 5)
      coupon = create(:coupon, discount: 5, duration: nil)
      @monthly_org.redeem_coupon(coupon)

      assert_money 15_00, @monthly_org.subscription.discounted_price
    end

    test "does not include coupon discount when the coupon is expiring" do
      @monthly_org.update(plan: "business", seats: 5)
      coupon = create(:coupon, discount: 5, duration: 1)

      Timecop.freeze(1.month.ago) { @monthly_org.redeem_coupon(coupon) }

      assert_money 20_00, @monthly_org.subscription.discounted_price
    end
  end

  context "#price_of_remaining_service" do
    test "10 days left on yearly" do
      Timecop.freeze(GitHub::Billing.timezone.local(2021, 6, 18)) do
        @org.seats = 6
        @org.billed_on = GitHub::Billing.today + 10.days

        # ($300 plan cost + $108 seats cost) * 9 / 365.0
        assert_money 7_09, @org.subscription.price_of_remaining_service
      end
    end

    test "10 days left on yearly ending before leap day" do
      Timecop.freeze(GitHub::Billing.timezone.local(2023, 1, 5)) do
        @org.seats = 6
        @org.billed_on = GitHub::Billing.today + 10.days
        # ($300 plan cost + $108 seats cost) * 9 / 365.0
        assert_money 7_09, @org.subscription.price_of_remaining_service
      end
    end

    test "10 days left on yearly ending after leap day" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 5)) do
        @org.seats = 6
        @org.billed_on = GitHub::Billing.today + 10.days
        # ($300 plan cost + $108 seats cost) * 9 / 366.0
        assert_money 7_08, @org.subscription.price_of_remaining_service
      end
    end

    test "10 days left on yearly starting after leap day" do
      Timecop.freeze(GitHub::Billing.timezone.local(2021, 5, 5)) do
        @org.seats = 6
        @org.billed_on = GitHub::Billing.today + 10.days

        assert_money 7_09, @org.subscription.price_of_remaining_service
      end
    end

    test "10 days left on monthly" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 5)) do
        @org.seats = 6
        @org.plan_duration = "month"
        @org.billed_on = GitHub::Billing.today + 10.days

        # (4 plan cost + $4 seats cost) * 9 / 30.0
        assert_money 7_18, @org.subscription.price_of_remaining_service
      end
    end

    test "10 days left on monthly bridging 30/31-day months" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 5)) do
        @org.seats = 6
        @org.plan_duration = "month"
        @org.billed_on = GitHub::Billing.today + 10.days
        assert_money 7_18, @org.subscription.price_of_remaining_service
      end
    end

    test "10 days left on monthly bridging 31/30-day months" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 6, 5)) do
        @org.seats = 6
        @org.plan_duration = "month"
        @org.billed_on = GitHub::Billing.today + 10.days

        assert_money 6_96, @org.subscription.price_of_remaining_service
      end
    end

    test "22 days left on monthly with round down" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 30)) do
        org = create :organization,
          plan: "business",
          admin: @owner,
          seats: 5,
          billed_on: GitHub::Billing.today + 12.days

        # $4 * 5 * % service remaining (11 of 31 days in May)
        # $4 * 5 * 11 / 31 = $7.08
        assert_equal Billing::Money.new(7_08), org.subscription.price_of_remaining_service
      end
    end

    test "10 days left on monthly with $5 credit balance" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 5, 15)) do
        user = create(:user, :zuora, plan: "large", plan_duration: "month",
          billed_on: GitHub::Billing.today + 10.days)
        create(:billing_plan_subscription, :zuora, user: user)

        # $50 plan cost * 9 / 30.0
        assert_money 14_99, user.subscription.price_of_remaining_service
      end
    end
  end

  context "#annual_discount_multiplier" do
    test "does not include coupon discount when the coupon is expiring" do
      assert_equal 0.083333333, @org.subscription.annual_discount_multiplier
    end
  end

  context "#discounted_plan_and_seat_cost" do
    test "passes through plan and seat cost" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        business = create(:business, :with_self_serve_payment, plan_duration: "month", seats: 2)
        business.customer.update(billing_end_date: 1.month.from_now)
        owner = business.owners.first

        create(:billing_product_uuid, :advanced_security)

        result = business.subscribe_to_advanced_security(
          actor: owner,
          seats: 1,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        # If Businesses implement coupons later, this test case will need to be updated
        assert_money 42_00, business.subscription.discounted_plan_and_seat_cost
      end
    end
  end

  context "#plan_and_seat_cost" do
    test "passes through plan and seat cost" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        business = create(:business, :with_self_serve_payment, plan_duration: "month", seats: 2)
        business.customer.update(billing_end_date: 1.month.from_now)
        owner = business.owners.first

        create(:billing_product_uuid, :advanced_security)

        result = business.subscribe_to_advanced_security(
          actor: owner,
          seats: 1,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        assert_money 42_00, business.subscription.plan_and_seat_cost
      end
    end
  end
end
