# typed: true
# frozen_string_literal: true

require "test_helper"

class SubscriptionItemInstrumentationTest < GitHub::TestCase
  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "subscription_item_created" do
    test "creates a transaction when a product_uuid item is purchased" do
      item = create :billing_subscription_item, :with_product_uuid, quantity: 1

      GitHub.instrument "billing.subscription_item_created",
        subscription_item_id: item.id,
        sender_id: item.account.id

      tx = item.account.transactions.last

      assert_equal tx.action, "sub_created"
      assert_equal tx.current_subscribable, item.subscribable
      assert_equal tx.current_subscribable_quantity, 1
    end

    test "emits metric to datadog" do
      item = create :billing_subscription_item, :with_product_uuid, quantity: 2

      GitHub.instrument "billing.subscription_item_created", subscription_item_id: item.id

      assert_incremented_stat("billing.subscription_item_created", tags: ["quantity:2"])
      assert_equal 2, GitHub.dogstats.counts("billing.subscription_item_created.units").first.value
    end
  end

  context "subscription_item_cancelled" do
    test "emits metric to datadog" do
      item = create :billing_subscription_item, :with_product_uuid, quantity: 1

      GitHub.instrument "billing.subscription_item_cancelled", subscription_item_id: item.id

      assert_incremented_stat("billing.subscription_item_cancelled", tags: ["quantity:1"])
    end
  end

  context "subscription_item_changed" do
    test "emits metric to datadog" do
      item = create :billing_subscription_item, :with_product_uuid, quantity: 3

      GitHub.instrument "billing.subscription_item_changed", subscription_item_id: item.id, old_quantity: 1, new_quantity: 3

      assert_incremented_stat("billing.subscription_item_changed", tags: ["quantity:3"])
    end
  end

  context "marketplace_purchase" do
    test "creates a transaction when a marketplace item is purchased" do
      item = create :billing_subscription_item,
        quantity: 2

      GitHub.instrument "marketplace_purchase.purchased",
        subscription_item_id: item.id,
        sender_id: item.account.id

      tx = item.account.transactions.last

      assert_equal tx.action, "mp_purchased"
      assert_equal tx.current_subscribable, item.subscribable
      assert_equal tx.current_subscribable_quantity, 2
    end

    test "creates a transaction for sponsorships when an item is purchased" do
      sponsor_item = create :sponsors_subscription_item,
        quantity: 2

      GitHub.instrument "sponsorship.added",
        subscription_item_id: sponsor_item.id,
        sender_id: sponsor_item.account.id

      tx = sponsor_item.account.transactions.last

      assert_equal tx.action, "sp_added"
      assert_equal tx.current_subscribable, sponsor_item.subscribable
      assert_equal tx.current_subscribable_quantity, 2
    end

    test "creates a transaction when a marketplace item is updated" do
      item = create :billing_subscription_item,
        quantity: 2
      old_listing_plan = create :marketplace_listing_plan,
        listing: item.listing

      GitHub.instrument "marketplace_purchase.changed",
        subscription_item_id: item.id,
        sender_id: item.account.id,
        previous_quantity: 4,
        previous_subscribable_id: old_listing_plan.id,
        previous_subscribable_type: old_listing_plan.class.name

      tx = item.account.transactions.last

      assert_equal tx.action, "mp_changed"
      assert_equal tx.current_subscribable, item.subscribable
      assert_equal tx.old_subscribable, old_listing_plan
      assert_equal tx.current_subscribable_quantity, 2
      assert_equal tx.old_subscribable_quantity, 4
    end

    test "creates a transaction for sponsorships when item is updated" do
      sponsor_item = create :sponsors_subscription_item,
        quantity: 2
      old_sponsors_tier = create :sponsors_tier,
        sponsors_listing: sponsor_item.listing,
        monthly_price_in_cents: sponsor_item.subscribable.monthly_price_in_cents + 1_00

      GitHub.instrument "sponsorship.changed",
        subscription_item_id: sponsor_item.id,
        sender_id: sponsor_item.account.id,
        previous_quantity: 4,
        previous_subscribable_id: old_sponsors_tier.id,
        previous_subscribable_type: old_sponsors_tier.class.name

      tx = sponsor_item.account.transactions.last

      assert_equal tx.action, "sp_changed"
      assert_equal tx.current_subscribable, sponsor_item.subscribable
      assert_equal tx.old_subscribable, old_sponsors_tier
      assert_equal tx.current_subscribable_quantity, 2
      assert_equal tx.old_subscribable_quantity, 4
    end

    test "creates a transaction when a marketplace item is cancelled" do
      item = create :billing_subscription_item,
        quantity: 2

      GitHub.instrument "marketplace_purchase.cancelled",
        subscription_item_id: item.id,
        sender_id: item.account.id

      tx = item.account.transactions.last

      assert_equal tx.action, "mp_cancelled"
      assert_equal tx.current_subscribable, item.subscribable
      assert_equal tx.current_subscribable_quantity, 2
    end

    test "creates a transaction for a sponsorship when an item is cancelled" do
      sponsor_item = create :sponsors_subscription_item,
        quantity: 2

      GitHub.instrument "sponsorship.cancelled",
        subscription_item_id: sponsor_item.id,
        sender_id: sponsor_item.account.id

      tx = sponsor_item.account.transactions.last

      assert_equal tx.action, "sp_cancelled"
      assert_equal tx.current_subscribable, sponsor_item.subscribable
      assert_equal tx.current_subscribable_quantity, 2
    end

    test "records the status of active listings" do
      active_listing = create(:marketplace_listing, :verified)
      plan = create(:marketplace_listing_plan, :published, listing: active_listing)
      item = create :billing_subscription_item,
        quantity: 2,
        subscribable: plan

      GitHub.instrument "marketplace_purchase.purchased",
        subscription_item_id: item.id,
        sender_id: item.account.id

      tx = item.account.transactions.last

      assert_equal "mp_purchased", tx.action
      assert_equal true, tx.active_listing?
    end

    test "records the status of inactive listings" do
      inactive_listing = create(:marketplace_listing, :draft)
      plan = create(:marketplace_listing_plan, :published, listing: inactive_listing)
      item = create :billing_subscription_item,
        quantity: 2,
        subscribable: plan

      GitHub.instrument "marketplace_purchase.purchased",
        subscription_item_id: item.id,
        sender_id: item.account.id

      tx = item.account.transactions.last

      assert_equal "mp_purchased", tx.action
      assert_equal false, tx.active_listing?
    end
  end
end
