# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class SubscriptionItemMarketplaceDependencyTest < GitHub::BillingTestCase
    context "#async_all_marketplace_listing_plan_ids_for_listing" do
      test "returns a list of all marketplace listing plans for the specified listing" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
        subscription_item = create(:billing_subscription_item,
          subscribable: listing_plan,
          quantity: 1)

        assert_equal [listing_plan.id], subscription_item.async_all_marketplace_listing_plan_ids_for_listing.sync
      end
    end

    context "for_marketplace_listing scope" do
      test "returns subscription items for any listing plan associated with the given listing" do
        listing = create(:marketplace_listing, :verified)
        listing_plan1, listing_plan2 = create_pair(:marketplace_listing_plan, :published, listing: listing)
        subscription_item1 = create(:billing_subscription_item, subscribable: listing_plan1, quantity: 1)
        subscription_item2, subscription_item3 = create_pair(:billing_subscription_item, subscribable: listing_plan2,
          quantity: 1)
        other_subscription_item = create(:billing_subscription_item, quantity: 1)

        result = Billing::SubscriptionItem.for_marketplace_listing(listing.id)

        refute_includes result, other_subscription_item
        assert_same_elements [subscription_item1, subscription_item2, subscription_item3], result
      end
    end

    context ".for_marketplace_listing" do
      test "includes active subscriptions for the specified listing" do
        listing = create(:marketplace_listing)
        listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
        other_listing = create(:marketplace_listing)
        other_listing_plan = create(:marketplace_listing_plan, :published, listing: other_listing)
        retired_listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
        active_subscription_item = create(:billing_subscription_item,
          subscribable: listing_plan,
          quantity: 2,
        )
        retired_subscription_item = create(:billing_subscription_item,
          subscribable: retired_listing_plan,
          quantity: 1,
        )
        retired_listing_plan.retire!(actor: listing.owner)
        other_subscription_item = create(:billing_subscription_item,
          subscribable: other_listing_plan,
          quantity: 1,
        )

        listing_plans_ids = Marketplace::ListingPlan.where(marketplace_listing_id: listing.id).
          pluck(:id)

        items = SubscriptionItem.for_marketplace_listing_plans(listing_plans_ids)
        assert_includes items, active_subscription_item
        assert_includes items, retired_subscription_item
        refute_includes items, other_subscription_item
      end
    end
  end
end
