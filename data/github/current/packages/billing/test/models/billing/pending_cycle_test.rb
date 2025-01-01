# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PendingCycleTest < GitHub::BillingTestCase

  context "#has_plan_changes?" do
    test "returns false when there are no pending plan changes" do
      user = create(:user)
      cycle = Billing::PendingCycle.new user

      refute cycle.has_plan_changes?
    end

    test "returns true when the pending plan change is changing duration" do
      org = create(:business_plus_org)
      cycle = Billing::PendingCycle.new org
      create :billing_pending_plan_change, user: org, plan_duration: User::BillingDependency::YEARLY_PLAN, seats: nil, plan: nil

      assert cycle.has_plan_changes?
    end

    test "returns true when the pending plan change is changing seats" do
      org = create(:business_plus_org)
      create :billing_pending_plan_change, user: org, plan_duration: nil, seats: 5, plan: nil
      cycle = Billing::PendingCycle.new org

      assert cycle.has_plan_changes?
    end

    test "returns true when the pending plan change is changing plan" do
      org = create(:business_plus_org)
      create :billing_pending_plan_change, user: org, plan_duration: nil, seats: 5, plan: GitHub::Plan.free

      cycle = Billing::PendingCycle.new org

      assert cycle.has_plan_changes?
    end
  end

  context "#seats" do
    test "returns the user's current seat count" do
      user = User.new seats: 3
      cycle = Billing::PendingCycle.new user

      assert_equal 3, cycle.seats
    end

    test "returns the pending seat count" do
      user = create :user, seats: 3
      create :billing_pending_plan_change, user: user, seats: 1
      cycle = Billing::PendingCycle.new user

      assert_equal 1, cycle.seats
    end

    test "doesn't use completed changes" do
      user = create :user, seats: 4
      create :billing_pending_plan_change, user: user, seats: 3, is_complete: true
      cycle = Billing::PendingCycle.new user

      assert_equal 4, cycle.seats
    end
  end

  context "#plan_duration" do
    test "returns the user's current plan duration" do
      user = User.new plan_duration: "year"
      cycle = Billing::PendingCycle.new user

      assert_equal "year", cycle.plan_duration
    end

    test "returns the pending plan duration" do
      user = create :user, plan_duration: "year"
      create :billing_pending_plan_change, user: user, plan_duration: "month"
      cycle = Billing::PendingCycle.new user

      assert_equal "month", cycle.plan_duration
    end

    test "doesn't use completed changes" do
      user = create :user, plan_duration: "month"
      create :billing_pending_plan_change, user: user, plan_duration: "year", is_complete: true
      cycle = Billing::PendingCycle.new user

      assert_equal "month", cycle.plan_duration
    end
  end

  context "#plan" do
    test "returns the current plan" do
      user = User.new plan: "pro"
      cycle = Billing::PendingCycle.new user

      assert_equal GitHub::Plan.pro, cycle.plan
    end

    test "returns the pending plan" do
      user = create :user, plan: "pro"
      create :billing_pending_plan_change, user: user, plan: "free"
      cycle = Billing::PendingCycle.new user

      assert_equal GitHub::Plan.free, cycle.plan
    end
  end

  context "#payment_amount" do
    test "monthly plan" do
      change = create :billing_pending_plan_change, plan: "small", plan_duration: "month"

      assert_equal 12, change.user.pending_cycle_payment_amount.dollars
    end

    test "yearly plan" do
      change = create :billing_pending_plan_change, plan: "small", plan_duration: "year"

      assert_equal 144, change.user.pending_cycle_payment_amount.dollars
    end

    test "monthly plan with a $ off discount" do
      change = create :billing_pending_plan_change, plan: "pro", plan_duration: "month"
      coupon = create :coupon, discount: "7"
      change.user.redeem_coupon coupon

      assert_equal GitHub::Plan.pro, change.user.pending_cycle_plan
      assert_equal 0, change.user.pending_cycle_payment_amount.dollars
    end

    test "business plan" do
      org = create(:organization)
      # not eligible for annual discount
      create(:billing_transaction,
        user: org,
        plan_name: "business",
        renewal_frequency: :yearly,
        amount_in_cents: 231_00
      )
      change = create :billing_pending_plan_change,
        plan: "business",
        plan_duration: "year",
        seats: 6,
        user: org,
        active_on: 1.year.from_now.to_date

      assert_equal 2_88, change.user.pending_cycle_payment_amount.dollars
    end

    test "business plan with discount" do
      org = create(:organization)
      create(:billing_transaction,
        user: org,
        plan_name: "business",
        renewal_frequency: :monthly,
        amount_in_cents: 4_00
      )
      change = create :billing_pending_plan_change,
        plan: "business",
        plan_duration: "year",
        seats: 6,
        user: org

      assert_equal 264, change.user.pending_cycle_payment_amount.dollars
    end

    test "monthly business plan without discount" do
      org = create(:organization)
      create(:billing_transaction,
        user: org,
        plan_name: "business",
        renewal_frequency: :monthly,
        amount_in_cents: 4_00
      )
      change = create :billing_pending_plan_change,
        plan: "business",
        plan_duration: "month",
        seats: 6,
        user: org

      assert_equal 24, change.user.pending_cycle_payment_amount.dollars
    end

    test "works with sub item changes" do
      user = create(:user)
      plan_subscription = create :billing_plan_subscription, user: user
      change = create :billing_pending_plan_change,
        user: user,
        actor: user,
        data_packs: nil,
        plan: "pro",
        seats: nil,
        plan_duration: "year"

      cheap_listing_plan = create :marketplace_listing_plan, :verified_listing,
        monthly_price_in_cents: 1_00,
        yearly_price_in_cents: 10_00
      create :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: cheap_listing_plan,
        quantity: 3

      old_listing_plan = create :marketplace_listing_plan, :verified_listing,
        monthly_price_in_cents: 10_00,
        yearly_price_in_cents: 100_00
      new_listing_plan = create :marketplace_listing_plan, :verified_listing,
        listing: old_listing_plan.listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 50_00
      subscription_item = create :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: old_listing_plan,
        quantity: 2
      mp_change = create :billing_pending_subscription_item_change,
        pending_plan_change: change,
        subscribable: new_listing_plan,
        quantity: 2

      expected_cost = new_listing_plan.yearly_price_in_cents * 2 + change.plan.yearly_cost_in_cents + cheap_listing_plan.yearly_price_in_cents * 3
      assert_equal expected_cost, change.user.pending_cycle_payment_amount.cents
    end
  end

  context "#plan_price" do
    test "passes through the current balance" do
      FakeZuora.mock
      plan_subscription = create(:billing_plan_subscription, :zuora, user: create(:user, :zuora))
      user = plan_subscription.user
      user.plan_subscription.update_attribute :balance_in_cents, -80_50
      create :billing_pending_plan_change, plan: "small", plan_duration: "year", user: user

      price = user.pending_cycle.payment_amount(use_balance: true)
      assert_equal Billing::Money.new(63_50), price
    end

    test "prorates the amount" do
      Timecop.freeze GitHub::Billing.timezone.local(2017, 4, 20) do
        FakeZuora.mock
        user = create(:user, :zuora, plan: GitHub::Plan.pro)
        create(:billing_plan_subscription, :zuora, user: user)

        daily_cost_in_cents = (user.plan.cost.to_f / 30) * 100
        assert_money (user.plan.cost_in_cents - daily_cost_in_cents).floor, user.pending_cycle.payment_amount(prorate: true)
      end
    end

    test "excludes copilot addon when include_addons: false" do
      user = create :user,
      plan: GitHub::Plan.free,
      plan_subscription: create(:billing_plan_subscription, :zuora)

      create(:billing_subscription_item, :paid,
        plan_subscription: user.plan_subscription,
        subscribable: create(:billing_product_uuid, :copilot, billing_cycle: :year)
      )

      price = user.pending_cycle(include_addons: false).payment_amount(use_balance: true)
      assert_equal Billing::Money.new(0), price
    end

    test "excludes copilot and ghas addon when include_addons: false" do
      user = create :user,
      plan: GitHub::Plan.free,
      plan_subscription: create(:billing_plan_subscription, :zuora)

      create(:billing_subscription_item, :paid,
        plan_subscription: user.plan_subscription,
        subscribable: create(:billing_product_uuid, :copilot, billing_cycle: :year)
      )

      create(:billing_subscription_item, :paid,
        plan_subscription: user.plan_subscription,
        subscribable: create(:billing_product_uuid, :advanced_security, billing_cycle: :month)
      )

      price = user.pending_cycle(include_addons: false).payment_amount(use_balance: true)
      assert_equal Billing::Money.new(0), price
    end

    test "includes copilot addon when include_addons: true" do
      user = create :user,
      plan: GitHub::Plan.free,
      plan_subscription: create(:billing_plan_subscription, :zuora)

      create(:billing_subscription_item, :paid,
        plan_subscription: user.plan_subscription,
        subscribable: create(:billing_product_uuid, :copilot, billing_cycle: :year)
      )

      price = user.pending_cycle(include_addons: true).payment_amount(use_balance: true)
      assert_equal Billing::Money.new(100_00), price
    end

    test "includes correct addon prices when include_addons: true and the addons have separate billing cycles" do
      user = create :user,
      plan: GitHub::Plan.free,
      plan_subscription: create(:billing_plan_subscription, :zuora)

      create(:billing_subscription_item, :paid,
        plan_subscription: user.plan_subscription,
        subscribable: create(:billing_product_uuid, :copilot, billing_cycle: :year)
      )

      create(:billing_subscription_item, :paid,
        plan_subscription: user.plan_subscription,
        subscribable: create(:billing_product_uuid, :advanced_security, billing_cycle: :month)
      )

      price = user.pending_cycle(include_addons: true).payment_amount(use_balance: true)
      assert_equal Billing::Money.new(149_00), price
    end
  end

  context "#discounted_data_packs_price" do
    test "includes the balance on the account" do
      FakeZuora.mock
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user
      user.plan_subscription.update(balance_in_cents: -100_00)
      create(:billing_pending_plan_change, data_packs: 0)

      assert_equal Billing::Money.new(-100_00), user.pending_cycle.discounted_data_packs_price
    end
  end
end
