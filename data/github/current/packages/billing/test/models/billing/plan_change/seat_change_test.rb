# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PlanChange::SeatChangeTest < GitHub::BillingTestCase
  fixtures do
    @owner = create(:user)
    @org   = create :organization, \
      admin: @owner,
      plan: "business",
      seats: 5,
      billed_on: GitHub::Billing.today + 1.year,
      plan_duration: "year"
  end

  setup do
    Organization.any_instance.stubs(:annual_discount_allowed?).returns(false)
  end

  def days_in_yearly_period_ending_on(end_date)
    (end_date - 1.year.ago(end_date)).to_f
  end

  context "#list_price" do
    test "for 10 day yearly" do
      @org.billed_on = GitHub::Billing.today + 10.days
      percent_service_remaining = 9 / days_in_yearly_period_ending_on(@org.billed_on)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 11)
      assert_money (48_00 * 6 * percent_service_remaining).to_i, seat_change.list_price
    end

    test "for 10 day yearly with discount" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(true)
      @org.billed_on = GitHub::Billing.today + 10.days
      percent_service_remaining = 9 / days_in_yearly_period_ending_on(@org.billed_on)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 11)
      assert_money (44_00 * 6 * percent_service_remaining).to_i, seat_change.list_price
    end

    test "for 10 day yearly ending before leap day with discount" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(true)
      Timecop.freeze(2022, 1, 5) do
        @org.billed_on = GitHub::Billing.today + 10.days
        percent_service_remaining = 9 / 365.0
        seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 11)

        assert_money (44_00 * 6 * percent_service_remaining).to_i, seat_change.list_price
      end
    end

    test "for 10 day yearly ending before leap day" do
      Timecop.freeze(2022, 1, 5) do
        @org.billed_on = GitHub::Billing.today + 10.days
        percent_service_remaining = 9 / 365.0
        seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 11)

        assert_money (48_00 * 6 * percent_service_remaining).to_i, seat_change.list_price
      end
    end

    test "for 10 day yearly ending after leap day" do
      Timecop.freeze(2020, 5, 5) do
        @org.billed_on = GitHub::Billing.today + 10.days
        percent_service_remaining = 9 / 366.0
        seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 11)
        assert_money (48_00 * 6 * percent_service_remaining).to_i, seat_change.list_price
      end
    end

    test "for 10 day yearly starting after leap day" do
      Timecop.freeze(2021, 5, 5) do
        @org.billed_on = GitHub::Billing.today + 10.days
        percent_service_remaining = 9 / 365.0
        seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 11)

        assert_money (48_00 * 6 * percent_service_remaining).to_i, seat_change.list_price
      end
    end

    test "for 10 day monthly" do
      Timecop.freeze(2020, 5, 5) do
        @org.plan_duration = "month"
        @org.billed_on = GitHub::Billing.today + 10.days
        percent_service_remaining = 9 / (@org.billed_on - 1.month.ago(@org.billed_on)).to_f
        seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 10)

        assert_money (4_00 * 5 * percent_service_remaining).to_i, seat_change.list_price
      end
    end

    test "for 10 day monthly bridging 30/31-day months" do
      Timecop.freeze(2020, 5, 5) do
        @org.plan_duration = "month"
        @org.billed_on = GitHub::Billing.today + 10.days
        percent_service_remaining = 9 / 30.0
        seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 10)

        assert_money (4_00 * 5 * percent_service_remaining).to_i, seat_change.list_price
      end
    end

    test "for 10 day monthly bridging 31/30-day months" do
      Timecop.freeze(2020, 6, 5) do
        @org.plan_duration = "month"
        @org.billed_on = GitHub::Billing.today + 10.days
        percent_service_remaining = 9 / 31.0
        seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 10)

        assert_money (4_00 * 5 * percent_service_remaining).to_i, seat_change.list_price
      end
    end

    test "is full period for upgrade from free" do
      @org.seats = 0
      @org.billed_on = nil
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 10)
      assert_money 48_00 + 48_00 * 9, seat_change.list_price
    end

    test "for billed_on today" do
      @org.billed_on = GitHub::Billing.today
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 10)
      assert_money 0, seat_change.list_price
    end

    test "for 1 day away from next billing date" do
      @org.billed_on = GitHub::Billing.today + 1.day
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 10)
      assert_money 0, seat_change.list_price
    end
  end

  context "#final_price" do
    test "correctly accounts for subscription items, which aren't changing" do
      @org.billed_on = Date.new(2020, 6, 1)

      plan_subscription = create(:billing_plan_subscription, user: @org)
      listing_plan = create :marketplace_listing_plan,
        :verified_listing,
        monthly_price_in_cents: 10_00
      create :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: listing_plan,
        quantity: 1

      # final_price will be prorated for 31 days on a yearly cycle
      # 366 days in 2020
      service_remaining = 31.0 / 366.0

      Timecop.freeze(Date.new(2020, 5, 1)) do
        seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 10)

        assert_money (240_00 * service_remaining).to_i, seat_change.final_price
      end
    end

    test "correctly accounts for subscription items, which aren't changing with discount" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(true)
      @org.billed_on = Date.new(2020, 6, 1)

      plan_subscription = create(:billing_plan_subscription, user: @org)
      listing_plan = create :marketplace_listing_plan,
        :verified_listing,
        monthly_price_in_cents: 10_00
      create :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: listing_plan,
        quantity: 1

      # final_price will be prorated for 31 days on a yearly cycle
      # 366 days in 2020
      service_remaining = 31.0 / 366.0

      Timecop.freeze(Date.new(2020, 5, 1)) do
        seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 10)

        assert_money ((240_00 - 240_00 * 8.3333333 / 100) * service_remaining).to_i, seat_change.final_price
      end
    end
  end

  context "#renewal_price" do
    test "respects percentage coupons" do
      @org.redeem_coupon(create(:coupon, code: "halfoff", discount: 0.5))

      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 6)

      assert_money ((48_00 + (48_00 * 5)) * 0.5).to_i, seat_change.renewal_price
    end

    test "respects 100%-off coupons" do
      @org.redeem_coupon(create(:coupon, code: "notsoprofitable", discount: 1.0))

      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 6)
      assert_money 0, seat_change.renewal_price
    end
  end

  context "#current_price" do
    test "applies annual discount" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(true)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 6)
      assert_money (44_00 * 6).to_i, seat_change.current_price
    end

    test "full price when discount when not available" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(false)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 6)
      assert_money (48_00 * 6).to_i, seat_change.current_price
    end
  end

  context "account with no credits" do
    test "prorated charge" do
      @org.billed_on = GitHub::Billing.today + 20.days
      percent_service_remaining = 19 / days_in_yearly_period_ending_on(@org.billed_on)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 6)

      assert_money (48_00 * 1 * percent_service_remaining).to_i, seat_change.payment_amount
    end

    test "prorated charge with percent off coupon on the business plan" do
      @org.redeem_coupon(create(:coupon, code: "halfoff", discount: 0.50))
      @org.plan = "business"
      @org.seats = 1
      @org.billed_on = GitHub::Billing.today + 20.days

      percent_service_remaining = 19 / days_in_yearly_period_ending_on(@org.billed_on)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 10)

      additional_seats_cost = 4_00 * 9 * 12 # $9 for each seat beyond 1 for 12 months

      assert_money (additional_seats_cost * percent_service_remaining * 0.5).to_i, seat_change.payment_amount
    end

    test "prorated charge with 100%-off coupon on the business plan" do
      @org.plan = "business"
      @org.seats = 1
      @org.billed_on = GitHub::Billing.today + 20.days
      @org.redeem_coupon(create(:coupon, code: "opensource", discount: 1.0))

      _percent_service_remaining = 19 / days_in_yearly_period_ending_on(@org.billed_on)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 121)

      assert_money 0, seat_change.payment_amount
    end

    test "removing seats with 100%-off coupon on the business plan" do
      @org.plan = "business"
      @org.seats = 121
      @org.billed_on = GitHub::Billing.today + 20.days
      @org.redeem_coupon(create(:coupon, code: "opensource", discount: 1.0))

      _percent_service_remaining = 19 / days_in_yearly_period_ending_on(@org.billed_on)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 1)

      assert_money 0, seat_change.payment_amount
    end

    test "prorated charge with dollar amount coupon on the business plan" do
      Timecop.freeze(2021, 1, 31) do
        @org.plan = "business"
        @org.seats = 2
        @org.billed_on = GitHub::Billing.today + 20.days
        @org.redeem_coupon(create(:coupon, code: "fivedollarsoff", discount: 5))

        percent_service_remaining = 19 / days_in_yearly_period_ending_on(@org.billed_on)
        seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 10)


        base_cost_per_month = 8_00 # Base cost is actually $4, but we have an additional seat adding up to $8 total
        monthly_cost_per_seat = 4_00
        number_of_seats_above_base = 8
        months_per_year = 12
        coupon_discount = 5_00

        old_cost = (base_cost_per_month - coupon_discount) * months_per_year
        new_cost = (base_cost_per_month - coupon_discount \
                    + (number_of_seats_above_base * monthly_cost_per_seat) \
                    ) * months_per_year

        prorated_cost = (new_cost - old_cost) * percent_service_remaining
        assert_money prorated_cost, seat_change.payment_amount
      end
    end

    test "prorated refund" do
      @org.seats = 10
      @org.billed_on = GitHub::Billing.today + 20.days
      percent_service_remaining = 19 / days_in_yearly_period_ending_on(@org.billed_on)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 5)


      assert_money (48_00 * 5 * percent_service_remaining).to_i, seat_change.credit_remaining
    end

    test "prorated refund with volume discount" do
      @org.seats = 140
      @org.billed_on = GitHub::Billing.today + 20.days
      percent_service_remaining = 19 / days_in_yearly_period_ending_on(@org.billed_on)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 120)

      assert_money 0, seat_change.payment_amount
      assert_money (48_00 * 20 * percent_service_remaining).to_i, seat_change.credit_remaining
    end
  end

  context "account with a credit" do
    test "all credit is used for prorated upgrade" do
      FakeZuora.mock
      Timecop.freeze(2020, 5, 5) do
        org = create :organization, :zuora,
          plan: "business",
          seats: 10,
          billed_on: GitHub::Billing.today + 10.days,
          plan_duration: "month"
        create(:billing_plan_subscription, :zuora, user: org, balance_in_cents: -10_00)
        seat_change = Billing::PlanChange::SeatChange.new(org.reload, seats: 20)

        price = (9 / 30.0) * 4_00 * 10
        assert_money price - 10_00, seat_change.payment_amount
        assert_money 10_00, seat_change.credit_used
        assert_money 0, seat_change.credit_remaining
      end
    end

    test "partial credit is used for a prorated upgrade" do
      FakeZuora.mock
      Timecop.freeze(2020, 5, 5) do
        org = create :organization, :zuora,
          plan: "business",
          seats: 10,
          billed_on: GitHub::Billing.today + 10.days,
          plan_duration: "month"
        create(:billing_plan_subscription, :zuora, user: org, balance_in_cents: -100_00)

        seat_change = Billing::PlanChange::SeatChange.new(org.reload, seats: 11)
        percent_remaining = 9 / 30.0

        assert_money 0, seat_change.payment_amount
        assert_money percent_remaining * 4_00, seat_change.credit_used
        assert_money 100_00 - (percent_remaining * 4_00), seat_change.credit_remaining
      end
    end

    test "increases credit on a downgrade" do
      FakeZuora.mock
      Timecop.freeze(2022, 1, 5) do
        org = create :organization, :zuora,
          plan: "business",
          seats: 20,
          billed_on: GitHub::Billing.today + 10.days,
          plan_duration: "year"
        create(:billing_plan_subscription, :zuora, user: org, balance_in_cents: -10_00)
        seat_change = Billing::PlanChange::SeatChange.new(org.reload, seats: 19)

        percent_service_remaining = 9 / days_in_yearly_period_ending_on(org.billed_on)

        refund_for_downgrade = percent_service_remaining * 48_00
        assert_money 0, seat_change.payment_amount
        assert_money 0, seat_change.credit_used
        assert_money 10_00 + refund_for_downgrade, seat_change.credit_remaining
      end
    end

    test "decreases credit on an upgrade" do
      FakeZuora.mock
      Timecop.freeze(2022, 1, 5) do
        org = create :organization, :zuora,
          plan: "business",
          seats: 20,
          billed_on: GitHub::Billing.today + 10.days,
          plan_duration: "year"
        create(:billing_plan_subscription, :zuora, user: org, balance_in_cents: -10_00)
        seat_change = Billing::PlanChange::SeatChange.new(org, seats: 21)

        percent_service_remaining = 9 / days_in_yearly_period_ending_on(org.billed_on)

        charge_for_upgrade = percent_service_remaining * 48_00
        assert_money 0, seat_change.payment_amount
        assert_money charge_for_upgrade, seat_change.credit_used
        assert_money 10_00 - charge_for_upgrade, seat_change.credit_remaining
      end
    end
  end

  context "#renewal_price" do
    test "calculates cost of existing seats and additional seats" do
      @org.seats = 40

      assert_money 48_00 + (48_00 * 39), Billing::PlanChange::SeatChange.new(@org, seats: 40).renewal_price
      assert_money 48_00 + (48_00 * 44), Billing::PlanChange::SeatChange.new(@org, seats: 45).renewal_price
    end

    test "calculates cost of a full year renewal" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(false)
      @org.seats = 40
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 50)

      assert_money 48_00 + (48_00 * 49), seat_change.renewal_price
    end

    test "calculates cost of a full year renewal from a subscription with discount" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(true)
      Organization.any_instance.stubs(:next_billing_date).returns(GitHub::Billing.today)
      @org.seats = 40
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 50)

      assert_money 48_00 + (48_00 * 49), seat_change.renewal_price
    end
  end

  context "#unit_price" do
    test "calculates unit_price of seats with annual discount" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(true)
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 50)

      assert_money 44_00, seat_change.unit_price
    end

    test "calculates unit_price of seats without annual discount" do
      seat_change = Billing::PlanChange::SeatChange.new(@org, seats: 50)

      assert_money 48_00, seat_change.unit_price
    end
  end

  test "current_price and renewal price reflect plan only when plan_and_seat_cost_only is true" do
    GitHub.flipper[:remove_enterprise_plan_annual_discount].enable
    jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
    travel_to jan_1st do
      business = create(:business, :with_self_serve_payment, plan_duration: "year", seats: 2)
      owner = business.owners.first

      create(:billing_product_uuid, :advanced_security)

      result = business.subscribe_to_advanced_security(
        actor: owner,
        seats: 1,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert result.ok?

      seat_change = Billing::PlanChange::SeatChange.new(business, seats: 3, plan_and_seat_cost_only: true)

      assert_money 756_00, seat_change.current_price
      assert_money 756_00, seat_change.renewal_price
    end
  end
end
