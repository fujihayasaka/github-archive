# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingPendingSubscriptionItemChangeTest < GitHub::TestCase
  include GitHub::BillingTest
  include HydroTestHelpers
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  context "#subscribable_name" do
    test "returns the product UUID name" do
      product_uuid = create(:billing_product_uuid, name: "A Nice Product")
      plan_sub = create(:billing_plan_subscription)
      pending_plan_change = create(:billing_pending_plan_change, user: plan_sub.user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, plan_subscription: plan_sub,
        subscribable: product_uuid, pending_plan_change: pending_plan_change)

      assert_equal "A Nice Product", pending_sub_item_change.subscribable_name
    end

    test "returns the Marketplace listing and Marketplace listing plan names" do
      listing_plan = create(:marketplace_listing_plan, :verified_listing)
      listing = listing_plan.listing
      plan_sub = create(:billing_plan_subscription)
      pending_plan_change = create(:billing_pending_plan_change, user: plan_sub.user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, plan_subscription: plan_sub,
        subscribable: listing_plan, pending_plan_change: pending_plan_change)

      assert_equal "#{listing.name} #{listing_plan.name}", pending_sub_item_change.subscribable_name
    end

    test "returns the Sponsors listing and tier names" do
      tier = create(:sponsors_tier, :approved_sponsors_listing)
      listing = tier.sponsors_listing
      plan_sub = create(:billing_plan_subscription)
      pending_plan_change = create(:billing_pending_plan_change, user: plan_sub.user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, plan_subscription: plan_sub,
        subscribable: tier, pending_plan_change: pending_plan_change)

      assert_equal "#{listing.slug} #{tier.name}", pending_sub_item_change.subscribable_name
    end
  end

  context "#abbr_prefix" do
    test "pending cycle displays with 'Sponsorship' info when the listable is sponsorable" do
      sponsor_change = create(:sponsors_pending_subscription_item_change)
      user = sponsor_change.pending_plan_change.user
      pending_cycle = user.pending_cycle
      pending_change = pending_cycle.pending_subscription_item_changes.last

      assert_equal "SP", pending_change.abbr_prefix
    end

    test "pending cycle display with 'Marketplace' info when the listable is NOT sponsorable" do
      marketplace_change = create(:billing_pending_subscription_item_change)
      user = marketplace_change.pending_plan_change.user
      pending_cycle = user.pending_cycle
      pending_change = pending_cycle.pending_subscription_item_changes.last

      assert_equal "MP", pending_change.abbr_prefix
    end
  end

  context "#abbr_title" do
    test "pending cycle displays with 'Sponsorship' info when the listable is sponsorable" do
      sponsor_change = create(:sponsors_pending_subscription_item_change)
      user = sponsor_change.pending_plan_change.user
      pending_cycle = user.pending_cycle
      pending_change = pending_cycle.pending_subscription_item_changes.last

      assert_equal "Sponsorship", pending_change.abbr_title
    end

    test "pending cycle display with 'Marketplace' info when the listable is NOT sponsorable" do
      marketplace_change = create(:billing_pending_subscription_item_change)
      user = marketplace_change.pending_plan_change.user
      pending_cycle = user.pending_cycle
      pending_change = pending_cycle.pending_subscription_item_changes.last

      assert_equal "Marketplace", pending_change.abbr_title
    end
  end

  context "#subscription_item" do
    test "raises when subscribable type is invalid" do
      pending_sub_item_change = create(:billing_pending_subscription_item_change)
      pending_sub_item_change.update_columns(subscribable_type: 3)

      error = assert_raises { pending_sub_item_change.subscription_item }

      assert_equal "Invalid subscribable type", error.message
    end

    test "returns the active subscription item on the change's plan subscription for its product UUID" do
      product_uuid = create(:billing_product_uuid)
      plan_sub = create(:billing_plan_subscription)
      pending_plan_change = create(:billing_pending_plan_change, user: plan_sub.user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, plan_subscription: plan_sub,
        subscribable: product_uuid, pending_plan_change: pending_plan_change)
      sub_item = create(:billing_subscription_item, subscribable: product_uuid, plan_subscription: plan_sub)

      assert_equal sub_item, pending_sub_item_change.subscription_item
    end

    test "returns the active subscription item on the change's plan subscription for its Sponsors tier" do
      sub_item = create(:sponsors_subscription_item)
      user = sub_item.user
      plan_sub = sub_item.plan_subscription
      tier = sub_item.subscribable
      pending_plan_change = create(:billing_pending_plan_change, user: user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, plan_subscription: plan_sub,
        subscribable: tier, pending_plan_change: pending_plan_change)


      assert_equal sub_item, pending_sub_item_change.subscription_item
    end

    test "returns an inactive subscription item for a Sponsors tier when no active item exists" do
      sub_item = create(:sponsors_subscription_item, :cancelled)
      user = sub_item.user
      plan_sub = sub_item.plan_subscription
      tier = sub_item.subscribable
      pending_plan_change = create(:billing_pending_plan_change, user: user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, plan_subscription: plan_sub,
        subscribable: tier, pending_plan_change: pending_plan_change)

      assert_equal sub_item, pending_sub_item_change.subscription_item
    end

    test "returns nil for a Sponsors tier when no inactive item exists" do
      sub_item = create(:sponsors_subscription_item, :cancelled)
      user = sub_item.user
      plan_sub = sub_item.plan_subscription
      tier = sub_item.subscribable
      pending_plan_change = create(:billing_pending_plan_change, user: user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, plan_subscription: plan_sub,
        subscribable: tier, pending_plan_change: pending_plan_change)
      sub_item.destroy

      assert_nil pending_sub_item_change.subscription_item
    end

    test "returns the active subscription item on the change's plan subscription for its Marketplace listing plan" do
      listing_plan = create(:marketplace_listing_plan, :verified_listing)
      plan_sub = create(:billing_plan_subscription)
      pending_plan_change = create(:billing_pending_plan_change, user: plan_sub.user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, plan_subscription: plan_sub,
        subscribable: listing_plan, pending_plan_change: pending_plan_change)
      sub_item = create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_sub)

      assert_equal sub_item, pending_sub_item_change.subscription_item
    end
  end

  context "#undo_trial_cancellation" do
    test "returns false when change is not a free trial and does not update its quantity" do
      change = create :billing_pending_subscription_item_change, :billing_product_uuid_subscribable, :cancellation

      refute change.undo_trial_cancellation

      refute change.free_trial
      assert_equal 0, change.quantity
    end

    test "returns false  when change is not a cancellation and does not update its quantity" do
      change = create :billing_pending_subscription_item_change,
        :billing_product_uuid_subscribable, :free_trial, quantity: 3

      refute change.undo_trial_cancellation

      assert change.free_trial
      assert_equal 3, change.quantity
    end

    test "updates its quantity back to the subscription item's quantity when it's a free trial cancellation" do
      change = create :billing_pending_subscription_item_change,
        :billing_product_uuid_subscribable, :free_trial, :cancellation
      subscription_item = create :billing_subscription_item,
        plan_subscription: change.plan_subscription,
        subscribable: change.subscribable,
        quantity: 3

      assert change.undo_trial_cancellation

      assert change.free_trial
      assert_equal subscription_item.quantity, change.quantity
    end
  end

  context "#run" do
    test "applies plan changes" do
      user = create(:user)
      org = create(:credit_card_org, admin: user)
      plan_subscription = create(:billing_plan_subscription, user: org)

      old_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      new_listing_plan = create(:marketplace_listing_plan, :published, listing: old_listing_plan.listing)

      subscription_item = create :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: old_listing_plan,
        quantity: 1

      change = create :billing_pending_plan_change,
        user: org,
        actor: user
      mp_change = create :billing_pending_subscription_item_change,
        pending_plan_change: change,
        subscribable: new_listing_plan,
        quantity: 3

      assert_no_difference "Billing::SubscriptionItem.active.count" do
        mp_change.run
      end

      item = org.subscription_items.active.first
      assert_equal 3, item.quantity
      assert_equal new_listing_plan, item.subscribable
    end

    test "schedules separate changes for separate mp items" do
      user = create(:user)
      org = create(:credit_card_org, admin: user)
      plan_subscription = create(:billing_plan_subscription, user: org)

      first_listing_plan = create(:marketplace_listing_plan, :published)
      second_listing_plan = create(:marketplace_listing_plan, :published)

      create :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: first_listing_plan,
        quantity: 1

      change = create :billing_pending_plan_change,
        user: org,
        actor: user
      first_mp_change = create :billing_pending_subscription_item_change,
        pending_plan_change: change,
        subscribable: first_listing_plan,
        quantity: 3

      create :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: second_listing_plan,
        quantity: 1

      second_mp_change = create :billing_pending_subscription_item_change,
        pending_plan_change: change,
        subscribable: second_listing_plan,
        quantity: 4

      assert_equal 2, change.pending_subscription_item_changes.count
    end
  end

  context "#price" do
    test "calculates the price based on listing plan and quantity" do
      listing_plan = create :marketplace_listing_plan,
        monthly_price_in_cents: 10_00,
        yearly_price_in_cents: 120_00
      change = create :billing_pending_subscription_item_change,
        subscribable: listing_plan,
        quantity: 4

      assert_equal Billing::Money.new(40_00), change.price
    end

    test "includes duration when calculating the price" do
      listing_plan = create :marketplace_listing_plan,
        monthly_price_in_cents: 10_00,
        yearly_price_in_cents: 120_00
      pending_change = create :billing_pending_plan_change,
        plan_duration: "year"
      change = create :billing_pending_subscription_item_change,
        subscribable: listing_plan,
        pending_plan_change: pending_change,
        quantity: 4

      assert_equal Billing::Money.new(480_00), change.price
    end

    test "prorates monthly price based on active_on" do
      Timecop.freeze(GitHub::Billing.timezone.local(2017, 9, 11)) do
        user = create :user, billed_on: GitHub::Billing.today + 1.week
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 10_00, has_free_trial: true
        plan_subscription = create(:billing_plan_subscription, user: user)
        create :billing_subscription_item,
          subscribable: listing_plan, account: user, plan_subscription: plan_subscription
        pending_change = create :billing_pending_plan_change,
          active_on: GitHub::Billing.today, user: user
        change = create :billing_pending_subscription_item_change,
          subscribable: listing_plan,
          pending_plan_change: pending_change,
          quantity: 4

        # $10 * 4 * 7 / 31
        assert_equal Billing::Money.new(9_03), change.price
      end
    end

    test "prorates yearly price based on active_on" do
      Timecop.freeze(GitHub::Billing.timezone.local(2017, 9, 11)) do
        user = create :user,
          billed_on: GitHub::Billing.today + 2.weeks, plan_duration: "year"
        listing_plan = create :marketplace_listing_plan,
          :published,
          monthly_price_in_cents: 10_00,
          yearly_price_in_cents: 120_00,
          has_free_trial: true
        plan_subscription = create(:billing_plan_subscription, user: user)
        create :billing_subscription_item,
          subscribable: listing_plan, account: user, plan_subscription: plan_subscription
        pending_change = create :billing_pending_plan_change,
          active_on: GitHub::Billing.today, user: user, plan_duration: "year"
        change = create :billing_pending_subscription_item_change,
          subscribable: listing_plan,
          pending_plan_change: pending_change,
          quantity: 4

        # $120 * 4 * 14 / 365
        assert_equal Billing::Money.new(18_41), change.price
      end
    end

    test "charges for a full month if trial ends on billing date" do
      Timecop.freeze(GitHub::Billing.timezone.local(2017, 9, 11)) do
        user = create :user, billed_on: GitHub::Billing.today + 1.week
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 10_00, has_free_trial: true
        plan_subscription = create(:billing_plan_subscription, user: user)
        create :billing_subscription_item,
          subscribable: listing_plan, account: user, plan_subscription: plan_subscription
        pending_change = create :billing_pending_plan_change,
          active_on: GitHub::Billing.today + 1.week, user: user
        change = create :billing_pending_subscription_item_change,
          subscribable: listing_plan,
          pending_plan_change: pending_change,
          quantity: 4

        assert_equal Billing::Money.new(40_00), change.price
      end
    end

    test "does not calculate a negative price when billed_on is before active_on for monthly users" do
      # This is a race condition that can occur when a free user (with a nil
      # billed_on) is signing up for a marketplace item with a free trial.
      Timecop.freeze(Date.new(2018, 2, 1)) do
        user = create(:user, billed_on: GitHub::Billing.today, plan_duration: User::BillingDependency::MONTHLY_PLAN)
        create(:billing_plan_subscription, user: user)

        listing_plan = create :marketplace_listing_plan,
          :published,
          monthly_price_in_cents: 10_00,
          has_free_trial: true

        pending_plan_change = create :billing_pending_plan_change,
          user: user,
          active_on: GitHub::Billing.today + 1.week,
          plan_duration: user.plan_duration
        pending_subscription_item_change = create :billing_pending_subscription_item_change,
          subscribable: listing_plan,
          pending_plan_change: pending_plan_change,
          quantity: 10

        # $10 item cost * 10 units * 21/31 days
        assert_money 67_74, pending_subscription_item_change.price
      end
    end

    test "does not calculate a negative price when billed_on is before active_on for yearly users" do
      # This is a race condition that can occur when a free user (with a nil
      # billed_on) is signing up for a marketplace item with a free trial.
      Timecop.freeze(Date.new(2018, 2, 1)) do
        user = create(:user, billed_on: GitHub::Billing.today, plan_duration: User::BillingDependency::YEARLY_PLAN)
        create(:billing_plan_subscription, user: user)

        listing_plan = create :marketplace_listing_plan,
          :published,
          yearly_price_in_cents: 100_00,
          has_free_trial: true

        pending_plan_change = create :billing_pending_plan_change,
          user: user,
          active_on: GitHub::Billing.today + 1.week,
          plan_duration: user.plan_duration
        pending_subscription_item_change = create :billing_pending_subscription_item_change,
          subscribable: listing_plan,
          pending_plan_change: pending_plan_change,
          quantity: 10

        # $100 item cost * 10 units * 358/365 days
        assert_money 980_82, pending_subscription_item_change.price
      end
    end
  end

  context ".trial_ending_in_four_days" do
    test "returns free trial item changes ending in exactly four days" do
      ending_in_four_days = create :billing_pending_plan_change, active_on: GitHub::Billing.today + 4.days
      ending_in_two_days = create :billing_pending_plan_change, active_on: GitHub::Billing.today + 2.days
      ending_in_six_days = create :billing_pending_plan_change, active_on: GitHub::Billing.today + 6.days
      also_ending_in_four_days = create :billing_pending_plan_change, active_on: GitHub::Billing.today + 4.days
      ending_in_eight_days = create :billing_pending_plan_change, active_on: GitHub::Billing.today + 8.days
      [
        ending_in_four_days,
        ending_in_two_days,
        ending_in_six_days,
        also_ending_in_four_days,
        ending_in_eight_days,
      ].each do |change|
        create :billing_pending_subscription_item_change,
          :free_trial,
          subscribable: create(:marketplace_listing_plan, :published, has_free_trial: true),
          pending_plan_change: change,
          quantity: 4
      end

      _active_in_four_days_but_not_a_free_trial =
        create :billing_pending_subscription_item_change,
        subscribable: create(:marketplace_listing_plan, :published, has_free_trial: true),
        pending_plan_change: ending_in_four_days,
        quantity: 4

      trials_ending_in_four_days = Billing::PendingSubscriptionItemChange.trial_ending_in_four_days

      assert_equal 2, trials_ending_in_four_days.count
      assert trials_ending_in_four_days.include?(ending_in_four_days.pending_subscription_item_changes.first)
      assert trials_ending_in_four_days.include?(also_ending_in_four_days.pending_subscription_item_changes.first)
    end
  end

  context "#active_subscription_item" do
    test "returns nil when the current subscribed to item is a sponsors_listing" do
      sub_item = create(:sponsors_subscription_item)
      user = sub_item.user
      plan_sub = sub_item.plan_subscription
      tier = sub_item.subscribable

      pending_plan_change = create(:billing_pending_plan_change, user: user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change,
        plan_subscription: plan_sub,
        subscribable: tier,
        quantity: 0,
        pending_plan_change: pending_plan_change)

      assert_nil pending_sub_item_change.active_subscription_item
    end

    test "returns nil when the current subscribed to item is a marketplace_listing_plan" do
      marketplace_listing = create(:marketplace_listing, :verified)
      listing_plan = create(:marketplace_listing_plan, :verified_listing,
        listing: marketplace_listing,
        monthly_price_in_cents: 10_00)
      other_listing_plan = create(:marketplace_listing_plan, :verified_listing,
        listing: marketplace_listing,
        monthly_price_in_cents: 5_00)
      plan_sub = create(:billing_plan_subscription)
      pending_plan_change = create(:billing_pending_plan_change, user: plan_sub.user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change,
        plan_subscription: plan_sub,
        subscribable: other_listing_plan,
        pending_plan_change: pending_plan_change)
      sub_item = create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_sub)

      assert_nil pending_sub_item_change.active_subscription_item
    end

    test "returns the active subscription item when the subscribable is a product_uuid" do
      currently_subscribed_product = create(:billing_product_uuid, billing_cycle: :year)
      other_product = create(:billing_product_uuid,
        product_type: currently_subscribed_product.product_type,
        product_key: currently_subscribed_product.product_key,
        billing_cycle: :month
      )
      plan_sub = create(:billing_plan_subscription)
      pending_plan_change = create(:billing_pending_plan_change, user: plan_sub.user)
      pending_sub_item_change = create(:billing_pending_subscription_item_change,
        plan_subscription: plan_sub,
        subscribable: other_product,
        pending_plan_change: pending_plan_change)
      sub_item = create(:billing_subscription_item,
        subscribable: currently_subscribed_product,
        plan_subscription: plan_sub)

      assert_equal sub_item, pending_sub_item_change.active_subscription_item
    end
  end

  test "instruments #create and #run" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    events = subscribe("pending_subscription_change.create")

    plan_subscription = create :billing_plan_subscription
    user = plan_subscription.user

    listing = create(:marketplace_listing, :verified)
    plan_was = create(:marketplace_listing_plan, :published, listing: listing)
    plan = create(:marketplace_listing_plan, :published, listing: listing)

    subscription_item = create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: plan_was,
      quantity: 1

    active_on = 1.month.from_now.to_date
    plan_change = create :billing_pending_plan_change,
      active_on: active_on,
      user: user,
      actor: user
    item_change = create :billing_pending_subscription_item_change,
      pending_plan_change: plan_change,
      subscribable: plan,
      quantity: 3

    assert event = events.pop, "expected an audit log event"
    assert_incremented_stat "billing.pending_subscription_change.create", tags: ["product:marketplace/listing_plan"]

    expected_payload = {
      active_on: active_on,
      actor_id: user.id,
      actor: user.login,
      user_id: user.id,
      user: user.login,
      subitm_codename: "marketplace/listing_plan",
      marketplace_listing_id: listing.id,
      marketplace_listing: listing.name,
      marketplace_listing_plan_was: plan_was.name,
      marketplace_listing_plan: plan.name,
      quantity_was: 1,
      quantity: 3,
      free_trial: false,
      id: item_change.id,
    }
    assert_equal expected_payload, event.payload

    events = subscribe("pending_subscription_change.run")
    item_change.run

    assert event = events.pop, "expected an audit log event"
    assert_incremented_stat "billing.pending_subscription_change.run", tags: ["product:marketplace/listing_plan"]

    expected_payload = {
      active_on: active_on,
      user_id: user.id,
      user: user.login,
      subitm_codename: "marketplace/listing_plan",
      marketplace_listing_id: listing.id,
      marketplace_listing: listing.name,
      marketplace_listing_plan: plan.name,
      quantity: 3,
      id: item_change.id,
      free_trial: false,
      success: true,
    }
    assert_equal expected_payload, event.payload
  end

  test "instruments #create with user as an org" do
    events = subscribe("pending_subscription_change.create")

    user = create(:user)
    org = create(:credit_card_org, admin: user)
    plan_subscription = create :billing_plan_subscription, user: user

    listing = create(:marketplace_listing, :verified)
    plan_was = create(:marketplace_listing_plan, :published, listing: listing)
    plan = create(:marketplace_listing_plan, :published, listing: listing)

    subscription_item = create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: plan_was,
      quantity: 1

    active_on = 1.month.from_now.to_date
    plan_change = create :billing_pending_plan_change,
      active_on: active_on,
      user: org,
      actor: user
    item_change = create :billing_pending_subscription_item_change,
      pending_plan_change: plan_change,
      subscribable: plan,
      quantity: 3

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: active_on,
      actor_id: user.id,
      actor: user.login,
      org_id: org.id,
      org: org.login,
      subitm_codename: "marketplace/listing_plan",
      marketplace_listing_id: listing.id,
      marketplace_listing: listing.name,
      marketplace_listing_plan: plan.name,
      quantity: 3,
      free_trial: false,
      id: item_change.id,
    }
    assert_equal expected_payload, event.payload
  end

  test "instruments #destroy" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    events = subscribe("pending_subscription_change.destroy")

    plan_subscription = create :billing_plan_subscription
    user = plan_subscription.user

    product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)

    subscription_item = create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: product_uuid,
      quantity: 1

    active_on = 1.month.from_now.to_date
    plan_change = create :billing_pending_plan_change,
      active_on: active_on,
      user: user,
      actor: user
    item_change = create :billing_pending_subscription_item_change,
      pending_plan_change: plan_change,
      subscribable: product_uuid,
      quantity: 0

    expected_payload = {
      active_on: active_on,
      subitm_codename: "github.advanced_security.v0.month",
      quantity: 0,
      free_trial: false,
      id: item_change.id,
      user: user.login,
      user_id: user.id,
      actor: user.login,
      actor_id: user.id
    }

    expected_log_keys = {
      active_on: active_on,
      quantity: 0,
      free_trial: false,
      id: item_change.id,
      user: user.login,
      actor: user.login,
    }
    assert_logged(**expected_log_keys) do
      item_change.destroy
    end

    assert event = events.pop, "expected an audit log event"
    assert_equal expected_payload, event.payload
    assert_incremented_stat "billing.pending_subscription_change.destroy", tags: ["product:github.advanced_security.v0.month"]
    assert span = find_span_by(name: "instrument_destroy")
    assert_same_hash({ "product" => "github.advanced_security.v0.month" }, span.attributes)
  end

  test "instruments an unsuccessful #run for a product_uuid" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    events = subscribe("pending_subscription_change.create")

    plan_subscription = create :billing_plan_subscription
    user = plan_subscription.user

    product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)

    subscription_item = create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: product_uuid,
      quantity: 1

    active_on = 1.month.from_now.to_date
    plan_change = create :billing_pending_plan_change,
      active_on: active_on,
      user: user,
      actor: user
    item_change = create :billing_pending_subscription_item_change,
      pending_plan_change: plan_change,
      subscribable: product_uuid,
      quantity: -1
    events = subscribe("pending_subscription_change.run")
    item_change.run

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: active_on,
      subitm_codename: "github.advanced_security.v0.month",
      user_id: user.id,
      user: user.login,
      quantity: -1,
      free_trial: false,
      id: item_change.id,
      success: false,
      errors: "Quantity must be greater than or equal to 0",
    }
    assert_equal expected_payload, event.payload
    assert_dogstats_increment 1, "billing.pending_subscription_change.error", tags: ["product:github.advanced_security.v0.month"]
  end

  test "instruments an unsuccessful #run" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    events = subscribe("pending_subscription_change.create")

    plan_subscription = create :billing_plan_subscription
    user = plan_subscription.user

    listing = create(:marketplace_listing, :verified)
    plan_was = create(:marketplace_listing_plan, :published, listing: listing)
    plan = create(:marketplace_listing_plan, :published, listing: listing)

    subscription_item = create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: plan_was,
      quantity: 1

    active_on = 1.month.from_now.to_date
    plan_change = create :billing_pending_plan_change,
      active_on: active_on,
      user: user,
      actor: user
    item_change = create :billing_pending_subscription_item_change,
      pending_plan_change: plan_change,
      subscribable: plan,
      quantity: -1
    events = subscribe("pending_subscription_change.run")
    item_change.run

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: active_on,
      user_id: user.id,
      user: user.login,
      subitm_codename: "marketplace/listing_plan",
      marketplace_listing_id: listing.id,
      marketplace_listing: listing.name,
      marketplace_listing_plan: plan.name,
      quantity: -1,
      free_trial: false,
      id: item_change.id,
      success: false,
      errors: "Quantity must be greater than or equal to 0",
    }
    assert_equal expected_payload, event.payload
    assert_incremented_stat "billing.pending_subscription_change.error"
  end

  test "creates Hydro event on destroy for Sponsors subscriptions" do
    tier = create(:sponsors_tier, :approved_sponsors_listing, :published)
    sponsorship = create(:sponsorship, :pending_cancellation, tier: tier)
    pending_change = sponsorship.subscription_item.pending_subscription_item_change
    sponsor = sponsorship.sponsor

    message = {
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      actor: Hydro::EntitySerializer.user(sponsor),
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
      tier: Hydro::EntitySerializer.sponsors_tier(tier),
    }

    pending_change.instrument_undo_sponsorship_cancellation(actor: sponsor)

    assert_hydro_published(message, schema: "github.sponsors.v1.UndoSponsorshipCancellation")
    assert_hydro_messages(count: 1, schema: "github.sponsors.v1.UndoSponsorshipCancellation")
  end

  test "no Hydro event is created on destroy for Marketplace subscriptions" do
    user = create(:user)
    plan_subscription = create(:billing_plan_subscription, user: user)
    mp_listing_plan = create(:marketplace_listing_plan, :verified_listing, :published)
    create(
      :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: mp_listing_plan,
    )
    pending_plan_change = create(:billing_pending_plan_change, user: user)
    change = create(
      :billing_pending_subscription_item_change,
      quantity: 3,
      pending_plan_change: pending_plan_change,
      subscribable: mp_listing_plan,
    )

    change.instrument_undo_sponsorship_cancellation(actor: user)

    refute_hydro_messages(schema: "github.sponsors.v1.UndoSponsorshipCancellation")
  end
end
