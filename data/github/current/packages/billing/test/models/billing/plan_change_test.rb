# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PlanChangeTest < GitHub::BillingTestCase
  fixtures do
    @user = create :user, plan: "small"
  end

  def build_change(user, old_plan, new_plan, new_duration_in_months = nil, starting_new_subscription = false)
    old_subscription = Billing::Subscription.for_account(user, plan: GitHub::Plan.find!(old_plan))
    new_subscription = Billing::Subscription.for_account(user, plan: GitHub::Plan.find!(new_plan), duration_in_months: new_duration_in_months)

    Billing::PlanChange.new(old_subscription, new_subscription, starting_new_subscription: starting_new_subscription)
  end

  context "change between free_with_addons and pro" do
    test "changing with free marketplace items doesn't prorate the cost" do
      user = create :user, plan: "free_with_addons"
      plan_subscription = create :billing_plan_subscription, user: user
      subscription_item = create(
        :billing_subscription_item,
        :free,
        plan_subscription: plan_subscription,
        quantity: 1,
      )
      change = build_change(user, "free_with_addons", "pro", nil, !user.external_subscription?)
      assert_money 4_00, change.price_difference
      assert_money 4_00, change.final_price(github_only: true)
      assert_money 4_00, change.renewal_price(github_only: true)
    end

    test "changing with non-free marketplace items prorates the cost" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 22, 8, 0, 0)) do
        user = create :user, plan: "free_with_addons"
        plan_subscription = create :billing_plan_subscription, :zuora, user: user
        subscription_item = create(
          :billing_subscription_item,
          subscribable: create(:marketplace_listing_plan, :published, :verified_listing),
          plan_subscription: plan_subscription,
          quantity: 1,
        )
        change = build_change(user, "free_with_addons", "pro", nil, !user.external_subscription?)
        assert_money 4_00, change.price_difference
        assert_money 3_87, change.final_price
        assert_money 4_00, change.renewal_price(github_only: true)
      end
    end
  end

  context "plan_and_seat_cost_only" do
    test "passes through plan and seat cost only when true" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        business = create(:business, :with_self_serve_payment, plan_duration: "month", seats: 2)
        business.customer.update(billing_end_date: 1.month.from_now)
        owner = business.owners.first

        create(:billing_product_uuid, :advanced_security)

        result = business.subscribe_to_advanced_security(
          seats: 2,
          actor: owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        old_subscription = Billing::Subscription.for_account(business)
        new_subscription = Billing::Subscription.for_account(business, seats: 3)

        change = Billing::PlanChange.new(old_subscription, new_subscription, plan_and_seat_cost_only: true)

        assert_money 63_00, change.renewal_price
        assert_money 63_00, change.renewal_list_price
        assert_money 21_00, change.price_difference
      end
    end

    test "also considers other add ons when false" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        business = create(:business, :with_self_serve_payment, plan_duration: "month", seats: 2)
        business.customer.update(billing_end_date: 1.month.from_now)
        owner = business.owners.first

        create(:billing_product_uuid, :advanced_security)

        result = business.subscribe_to_advanced_security(
          seats: 2,
          actor: owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        old_subscription = Billing::Subscription.for_account(business)
        new_subscription = Billing::Subscription.for_account(business, seats: 3)

        change = Billing::PlanChange.new(old_subscription, new_subscription, plan_and_seat_cost_only: false)

        assert_money 161_00, change.renewal_price
        assert_money 161_00, change.renewal_list_price
        assert_money 21_00, change.price_difference
      end
    end
  end

  context "change between monthly plans" do
    test "free to micro" do
      @user.billed_on = GitHub::Billing.today + 10.days
      change = build_change(@user, "free", "micro", nil, !@user.external_subscription?)
      assert_money 7_00, change.price_difference
      assert_money 7_00, change.final_price
      assert_money 7_00, change.renewal_price
    end

    test "micro to free" do
      Timecop.freeze(2021, 3, 1) do
        @user.billed_on = GitHub::Billing.today + 10.days
        change = build_change(@user, "micro", "free")
        assert_money -7_00, change.price_difference
        assert_money 0_00, change.renewal_price

        # We have 9 days left in the billing cycle (one day less than the next
        # billed_on) and last month was February (a month with 28 days). We need
        # to refund $2.25.
        #
        # (-$7 / 28 days) * 9 = -$2.25
        assert_money -2_25, change.final_price
      end
    end

    test "small to medium" do
      Timecop.freeze(2015, 4, 1) do
        @user.billed_on = GitHub::Billing.today + 15.days
        change = build_change(@user, "small", "medium")
        assert_money 10_00, change.price_difference
        assert_money 22_00, change.renewal_price

        # We have 14 days left in the billing cycle (one day less than the next
        # billed_on) and last month was March (a month with 31 days). We need to
        # charge $4.52.
        #
        # ($10 / 31 days) * 14 = $4.51 (4.5161, but round down)
        assert_money 4_51, change.final_price
      end
    end

    test "medium to small" do
      Timecop.freeze(2015, 5, 1) do
        @user.billed_on = GitHub::Billing.today + 20.days
        change = build_change(@user, "medium", "small")
        assert_money -10_00, change.price_difference
        assert_money 12_00, change.renewal_price

        # We have 19 days left in the billing cycle (one day less then next
        # billed_on) and last month was April (a month with 30 days). We need to
        # refund $6.33.
        #
        # (-$10 / 30 days) * 19 = -$6.33 (6.333333)
        assert_money -6_33, change.final_price
      end
    end
  end

  context "change between yearly plans" do
    test "free to medium" do
      @user.plan_duration = "year"
      @user.billed_on = GitHub::Billing.today + 140.days
      change = build_change(@user, "free", "medium", nil, !@user.external_subscription?)
      assert_money 12 * 22_00, change.price_difference
      assert_money 12 * 22_00, change.final_price
      assert_money 12 * 22_00, change.renewal_price
    end

    test "medium to free" do
      Timecop.freeze(2015, 1, 1) do
        @user.plan_duration = "year"
        @user.billed_on = GitHub::Billing.today + 40.days
        change = build_change(@user, "medium", "free")

        assert_money 12 * -22_00, change.price_difference
        assert_money 0, change.renewal_price

        # We have 39 days left in the billing cycle (one day less than the next
        # billed_on) and the billing cycle is a full year (365 days). We need to
        # refund $28.21.
        #
        # ((-$22 * 12) / 365 days) * 39 = -$28.20 (28.2082, but round down)
        assert_money -28_20, change.final_price
      end
    end

    test "pro to pro yearly" do
      Timecop.freeze(2015, 1, 1) do
        plan = GitHub::Plan.pro
        plan_subscription = create(
          :billing_plan_subscription,
          :zuora,
          user: create(
            :user,
            :zuora,
            plan: plan,
            plan_duration: User::BillingDependency::MONTHLY_PLAN,
            billed_on: GitHub::Billing.today + 15.days,
          ),
          balance_in_cents: -100_00,
        )
        change = build_change(plan_subscription.user, "pro", "pro", 12, nil)

        assert_money plan.yearly_cost_in_cents,  change.renewal_price
        assert_money (plan.cost_in_cents * (14.to_f / 31)).to_i, change.old_subscription.price_of_remaining_service
        assert_money plan_subscription.balance_in_cents + plan.yearly_cost_in_cents, change.final_price(use_balance: true)
      end
    end

    test "pro yearly to pro monthly when past due" do
      Timecop.freeze(2015, 1, 1) do
        plan = GitHub::Plan.pro
        plan_subscription = create(
          :billing_plan_subscription,
          :zuora,
          user: create(
            :user,
            :zuora,
            plan: plan,
            plan_duration: User::BillingDependency::YEARLY_PLAN,
            billed_on: GitHub::Billing.today - 1.day,
          ),
          balance_in_cents: 84_00,
        )
        change = build_change(plan_subscription.user, "pro", "pro", 1)

        assert_money plan.cost_in_cents, change.renewal_price
        assert_money plan.cost_in_cents, change.final_price(use_balance: true)
        assert_money 0, change.balance
      end
    end

    test "small to medium" do
      Timecop.freeze(2015, 2, 1) do
        @user.plan_duration = "year"
        @user.billed_on = GitHub::Billing.today + 110.days
        change = build_change(@user, "small", "medium")

        assert_money 12 * 10_00, change.price_difference
        assert_money 12 * 22_00, change.renewal_price

        # We have 109 days left in the billing cycle (one day less than the next
        # billed_on) and the billing cycle is a full year (365 days). We need to
        # charge $35.84.
        #
        # (($10 * 12) / 365 days) * 109 = $35.83 (35.8356, but round down)
        assert_money 35_83, change.final_price
      end
    end

    test "medium to small" do
      Timecop.freeze(2015, 10, 1) do
        @user.plan_duration = "year"
        @user.billed_on = GitHub::Billing.today + 201.days
        change = build_change(@user, "medium", "small")

        assert_money 12 * -10_00, change.price_difference
        assert_money 12 * 12_00, change.renewal_price

        # We have 200 days left in the billing cycle (one day less than the next
        # billed_on) and the billing cycle is a full year (366 days because 2016
        # is a leap year). We need to refund $65.57.
        #
        # ((-$10 * 12) / 366 days) * 200 = -$65.57
        assert_money -65_57, change.final_price
      end
    end

    test "small to medium using a balance" do
      Timecop.freeze(2015, 10, 1) do
        plan_subscription = create(
          :billing_plan_subscription,
          :zuora,
          user: create(
            :user,
            :zuora,
            plan_duration: User::BillingDependency::YEARLY_PLAN,
            plan: GitHub::Plan.small,
            billed_on: GitHub::Billing.today + 110.days,
          ),
          balance_in_cents: -1_00,
        )

        change = build_change(plan_subscription.user, "small", "medium")

        assert_money 34_83, change.final_price(use_balance: true)
      end
    end
  end

  context "#subscription_items_delta" do
    test "doesn't return free trials that have already ended" do
      user = create(:credit_card_user, plan: GitHub::Plan.pro)
      plan_subscription = create(:billing_plan_subscription, user: user)
      ended_trial = create :billing_subscription_item,
        :free_trial,
        plan_subscription: plan_subscription
      ended_trial.update(free_trial_ends_on: 1.week.ago)
      trial = create :billing_subscription_item,
        :free_trial,
        plan_subscription: plan_subscription

      old_subscription = Billing::Subscription.for_account(
          user,
          plan: user.plan,
          subscription_items: [ended_trial.dup, trial.dup],
      )
      trial.update(free_trial_ends_on: GitHub::Billing.yesterday)
      trial.reload
      new_subscription = Billing::Subscription.for_account \
        user,
        plan: GitHub::Plan.pro,
        subscription_items: [ended_trial, trial]
      plan_change = Billing::PlanChange.new \
        old_subscription,
        new_subscription

      assert plan_change.subscription_items_delta.include?(trial)
      refute plan_change.subscription_items_delta.include?(ended_trial)
    end

    test "returns items whose quantity has changed" do
      user = create(:credit_card_user, plan: GitHub::Plan.pro)
      plan_subscription = create(:billing_plan_subscription, user: user)
      listing_plan = create :marketplace_listing_plan,
        :published,
        monthly_price_in_cents: 5_00,
        has_free_trial: true
      trial_item = create :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: listing_plan,
        quantity: 3,
        free_trial_ends_on: GitHub::Billing.today + 14.days
      changing_quantity_item = create :billing_subscription_item,
        plan_subscription: plan_subscription,
        quantity: 1

      user.reload
      old_subscription = user.subscription
      trial_item.update(free_trial_ends_on: GitHub::Billing.yesterday)
      trial_item.reload
      changing_quantity_item.quantity = 2
      new_subscription = Billing::Subscription.for_account \
        user,
        plan: GitHub::Plan.pro,
        subscription_items: [trial_item, changing_quantity_item]
      plan_change = Billing::PlanChange.new \
        old_subscription,
        new_subscription

      assert plan_change.subscription_items_delta.include?(trial_item)
      quantity_delta = plan_change.subscription_items_delta.last
      assert_equal quantity_delta.quantity, 1
    end
  end

  context "#prorated_mp_price_for" do
    test "returns the default price when an existing item doesn't exist for the listing" do
      item = create :billing_subscription_item, quantity: 1
      old_subscription = Billing::Subscription.for_account item.user,
        subscription_items: []
      new_subscription = Billing::Subscription.for_account item.user,
        subscription_items: [item]
      change = Billing::PlanChange.new(old_subscription, new_subscription)

      price = change.prorated_mp_price_for \
        subscription_item: item,
        service_percent_remaining: 1

      assert_equal item.base_price, price
    end

    test "calculates the price based on service_percent_remaining" do
      listing_plan = create :marketplace_listing_plan, :published, monthly_price_in_cents: 10_00
      item = create :billing_subscription_item, quantity: 1, subscribable: listing_plan
      old_subscription = Billing::Subscription.for_account item.user,
        subscription_items: []
      new_subscription = Billing::Subscription.for_account item.user,
        subscription_items: [item]
      change = Billing::PlanChange.new(old_subscription, new_subscription)

      price = change.prorated_mp_price_for \
        subscription_item: item,
        service_percent_remaining: 0.5

      assert_money 5_00, price
    end

    test "discounts previously paid amonut when upgrading to a new plan" do
      listing = create(:marketplace_listing, :verified)
      listing_plan = create :marketplace_listing_plan, :published,
        listing: listing,
        monthly_price_in_cents: 10_00
      upgraded_listing_plan = create :marketplace_listing_plan, :published,
        listing: listing,
        monthly_price_in_cents: 20_00

      item = create :billing_subscription_item,
        subscribable: listing_plan,
        quantity: 0
      user = item.user.reload
      upgraded_item = create :billing_subscription_item,
        subscribable: upgraded_listing_plan,
        plan_subscription: user.plan_subscription,
        quantity: 1

      create :billing_transaction_line_item,
        billing_transaction: create(:billing_transaction, user: user),
        subscribable: listing_plan,
        amount_in_cents: 6_00,
        quantity: 1

      old_subscription = Billing::Subscription.for_account user,
        subscription_items: [item]
      new_subscription = Billing::Subscription.for_account user,
        subscription_items: [upgraded_item]
      change = Billing::PlanChange.new(old_subscription, new_subscription)

      price = change.prorated_mp_price_for \
        subscription_item: upgraded_item,
        service_percent_remaining: 0.5

      assert_money 4_00, price
    end

    test "doesn't show a credit when downgrading a plan early" do
      listing = create(:marketplace_listing, :verified)
      listing_plan = create :marketplace_listing_plan, :published,
        listing: listing,
        monthly_price_in_cents: 10_00
      downgraded_listing_plan = create :marketplace_listing_plan, :published,
        listing: listing,
        monthly_price_in_cents: 5_00

      item = create :billing_subscription_item,
        subscribable: listing_plan,
        quantity: 0
      user = item.user.reload
      downgraded_item = create :billing_subscription_item,
        subscribable: downgraded_listing_plan,
        plan_subscription: user.plan_subscription,
        quantity: 1

      create :billing_transaction_line_item,
        billing_transaction: create(:billing_transaction, user: user),
        subscribable: listing_plan,
        amount_in_cents: 6_00,
        quantity: 1

      old_subscription = Billing::Subscription.for_account user,
        subscription_items: [item]
      new_subscription = Billing::Subscription.for_account user,
        subscription_items: [downgraded_item]
      change = Billing::PlanChange.new(old_subscription, new_subscription)

      price = change.prorated_mp_price_for \
        subscription_item: downgraded_item,
        service_percent_remaining: 0.5

      assert_money 0, price
    end
  end
end
