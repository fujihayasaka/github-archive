# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class SubscriptionItemSponsorsDependencyTest < GitHub::BillingTestCase
    context "#sponsorship_specific_plan_subscription?" do
      test "true when plan subscription has purpose=sponsors" do
        plan_subscription = build(:billing_plan_subscription, purpose: :sponsors)
        assert_predicate plan_subscription, :sponsors_purpose?
        subscription_item = build(:billing_subscription_item, plan_subscription: plan_subscription)
        assert_predicate subscription_item, :sponsorship_specific_plan_subscription?
      end

      test "false when plan subscription has purpose=general" do
        plan_subscription = build(:billing_plan_subscription)
        assert_predicate plan_subscription, :general_purpose?
        subscription_item = build(:billing_subscription_item, plan_subscription: plan_subscription)
        refute_predicate subscription_item, :sponsorship_specific_plan_subscription?
      end
    end

    context "#stale_one_time_sponsorship?" do
      test "returns false for recent one-time sponsorship subscription item" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)
        sponsorship = create(:sponsorship, tier: tier)
        item = sponsorship.subscription_item

        refute_predicate item, :stale_one_time_sponsorship?
      end

      test "returns false for one-time sponsorship subscription item without an update time" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)
        sponsorship = create(:sponsorship, tier: tier)
        item = sponsorship.subscription_item
        item.update_column(:updated_at, nil)

        refute_predicate item, :stale_one_time_sponsorship?
      end

      test "returns true for old one-time sponsorship subscription item" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        one_time_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)

        not_recent_enough = (Billing::SubscriptionItem::SponsorsDependency::ONE_TIME_STALE_THRESHOLD + 1.minute).ago
        subscription_item = travel_to not_recent_enough do
          create(:sponsors_subscription_item, subscribable: one_time_tier)
        end

        assert_predicate subscription_item, :stale_one_time_sponsorship?
      end

      test "returns false for old one-time subscription item that is not a sponsorship" do
        copilot_uuid = create(:billing_product_uuid, :copilot)

        not_recent_enough = (Billing::SubscriptionItem::SponsorsDependency::ONE_TIME_STALE_THRESHOLD + 1.minute).ago
        subscription_item = travel_to not_recent_enough do
          create(:billing_subscription_item, subscribable: copilot_uuid)
        end

        refute_predicate subscription_item, :stale_one_time_sponsorship?
      end
    end

    context "#sponsorship_specific_customer?" do
      test "true when plan subscription's customer has purpose=sponsors" do
        customer = create(:customer, purpose: :sponsors)
        assert_predicate customer, :sponsors_purpose?
        plan_subscription = create(:billing_plan_subscription, :sponsors_invoiced, customer: customer)
        subscription_item = build(:billing_subscription_item, plan_subscription: plan_subscription)
        assert_predicate subscription_item, :sponsorship_specific_customer?
      end

      test "false when plan subscription's customer has purpose=general" do
        customer = build(:customer)
        assert_predicate customer, :general_purpose?
        plan_subscription = build(:billing_plan_subscription, customer: customer)
        subscription_item = build(:billing_subscription_item, plan_subscription: plan_subscription)
        refute_predicate subscription_item, :sponsorship_specific_customer?
      end
    end

    context "at_sponsors_tier_price scope" do
      test "includes all subscription items using a Sponsors tier at the specified monthly cost" do
        listing = create(:sponsors_listing, :approved, :with_tier)
        common_price = 500_00 # specify a high common price to avoid flaking due to the sequence
        tier1 = create(:sponsors_tier, :custom, sponsors_listing: listing,
          monthly_price_in_cents: common_price)
        tier2 = create(:sponsors_tier, :custom, sponsors_listing: listing)
        tier3 = create(:sponsors_tier, :custom, sponsors_listing: listing,
          monthly_price_in_cents: common_price)
        tier4 = create(:sponsors_tier, :custom,
          monthly_price_in_cents: common_price)

        sub_item1 = create(:sponsors_subscription_item,
          account: tier1.creator,
          subscribable: tier1)
        sub_item2 = create(:sponsors_subscription_item,
          account: tier2.creator,
          subscribable: tier2)
        sub_item3 = create(:sponsors_subscription_item,
          account: tier3.creator,
          subscribable: tier3)
        sub_item4 = create(:sponsors_subscription_item,
          account: tier4.creator,
          subscribable: tier4)

        result = Billing::SubscriptionItem
          .at_sponsors_tier_price(common_price, listing_id: listing.id)
          .where(id: [sub_item1, sub_item2, sub_item3, sub_item4])

        assert_includes result, sub_item1
        refute_includes result, sub_item2,
          "should not include subscription item at a different price point"
        assert_includes result, sub_item3
        refute_includes result, sub_item4,
          "should not include subscription item for a different listing"
      end
    end

    context "#one_time_sponsorship?" do
      test "returns true when subscribable is a one-time Sponsors tier" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)
        sponsorship = create(:sponsorship, tier: tier)
        item = sponsorship.subscription_item

        assert_predicate item, :one_time_sponsorship?
      end

      test "returns false when subscribable is a recurring Sponsors tier" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, frequency: :recurring, sponsors_listing: listing)
        sponsorship = create(:sponsorship, tier: tier)
        item = sponsorship.subscription_item

        refute_predicate item, :one_time_sponsorship?
      end

      test "returns false when subscribable is not a Sponsors tier" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
        subscription_item = create(:billing_subscription_item, subscribable: listing_plan)

        refute_predicate subscription_item, :one_time_sponsorship?
      end
    end

    context "#recurring_sponsorship?" do
      test "returns true when subscribable is a recurring Sponsors tier" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, :recurring, sponsors_listing: listing)
        sponsorship = create(:sponsorship, tier: tier)
        item = sponsorship.subscription_item

        assert_predicate item, :recurring_sponsorship?
      end

      test "returns false when subscribable is a one-time Sponsors tier" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)
        sponsorship = create(:sponsorship, tier: tier)
        item = sponsorship.subscription_item

        refute_predicate item, :recurring_sponsorship?
      end

      test "returns false when subscribable is not a Sponsors tier" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
        subscription_item = create(:billing_subscription_item, subscribable: listing_plan)

        refute_predicate subscription_item, :recurring_sponsorship?
      end
    end

    context "#sponsorable_id" do
      test "returns the ID of the sponsorable if the subscribable is a SponsorsTier" do
        tier = create(:sponsors_tier, :approved_sponsors_listing)
        sponsorship = create(:sponsorship, tier: tier)
        assert_equal tier.sponsorable_id, sponsorship.subscription_item.sponsorable_id
      end

      test "returns nil if the subscribable is not a SponsorsTier" do
        listing_plan = create :marketplace_listing_plan, :published
        subscription_item = create :billing_subscription_item, subscribable: listing_plan, quantity: 1
        assert_nil subscription_item.sponsorable_id
      end
    end

    context "#sponsored_organization?" do
      test "returns true when the subscription item's subscribable is a Sponsors tier for an organization" do
        listing = create(:sponsors_listing, :approved, :for_org, tier_count: 1)
        tier = listing.default_tier
        sponsorship = create(:sponsorship, tier: tier)
        item = sponsorship.subscription_item

        assert_predicate item, :sponsored_organization?
      end

      test "returns false when the subscription item's subscribable is a Sponsors tier for a user" do
        item = create(:sponsors_subscription_item)
        refute_predicate item, :sponsored_organization?
      end

      test "returns false when the subscription item's subscribable is not a Sponsors tier" do
        listing_plan = create(:marketplace_listing_plan, :published)
        subscription_item = create(:billing_subscription_item, subscribable: listing_plan, quantity: 1)

        refute_predicate subscription_item, :sponsored_organization?
      end
    end

    context "#sponsored_user?" do
      test "returns true when the subscription item's subscribable is a Sponsors tier for a user" do
        item = create(:sponsors_subscription_item)
        assert_predicate item, :sponsored_user?
      end

      test "returns false when the subscription item's subscribable is a Sponsors tier for an organization" do
        listing = create(:sponsors_listing, :approved, :for_org, tier_count: 1)
        tier = listing.default_tier
        sponsorship = create(:sponsorship, tier: tier)
        item = sponsorship.subscription_item

        refute_predicate item, :sponsored_user?
      end

      test "returns false when the subscription item's subscribable is not a Sponsors tier" do
        listing_plan = create(:marketplace_listing_plan, :published)
        subscription_item = create(:billing_subscription_item, subscribable: listing_plan, quantity: 1)

        refute_predicate subscription_item, :sponsored_user?
      end
    end

    context "#sponsorable and #async_sponsorable" do
      # https://github.com/github/sponsors/issues/5352
      test "returns nil when Sponsors tier no longer exists" do
        tier = create(:sponsors_tier, :published)
        sub_item = create(:sponsors_subscription_item, subscribable: tier)
        tier.delete

        assert_nil sub_item.reload.async_sponsorable.sync
        assert_nil sub_item.sponsorable
      end

      test "returns the sponsorable if the subscribable is a SponsorsTier" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, sponsors_listing: listing)
        item = create(:sponsors_subscription_item, subscribable: tier)

        assert_equal listing.owner, item.async_sponsorable.sync
        assert_equal listing.owner, item.sponsorable
      end

      test "returns nil if the subscribable is not a SponsorsTier" do
        listing_plan = create :marketplace_listing_plan,
          :published
        subscription_item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 1

        assert_nil subscription_item.async_sponsorable.sync
        assert_nil subscription_item.sponsorable
      end
    end

    context "#async_all_sponsors_tier_ids_for_listing" do
      test "returns a list of all tier ids for the specified listing" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, sponsors_listing: listing)
        tier2 = create(:sponsors_tier, :published, sponsors_listing: listing)
        sponsorship = create(:sponsorship, tier: tier)
        sponsorship2 = create(:sponsorship, tier: tier2)
        item = sponsorship.subscription_item

        assert_equal [tier.id, tier2.id], item.async_all_sponsors_tier_ids_for_listing.sync
      end
    end

    context ".for_sponsors_listing" do
      test "includes subscription items for the specified listing" do
        tier = create(:sponsors_tier, :approved_sponsors_listing)
        sponsors_listing = tier.listing
        retired_tier = create(:sponsors_tier, :published, sponsors_listing: sponsors_listing)
        other_tier = create(:sponsors_tier, :approved_sponsors_listing)

        active_subscription_item = create(:sponsors_subscription_item,
          subscribable: tier,
          quantity: 2)

        retired_subscription_item = create(:sponsors_subscription_item,
          subscribable: retired_tier,
          quantity: 1)
        retired_tier.retire!

        other_subscription_item = create(:sponsors_subscription_item,
          subscribable: other_tier,
          quantity: 1)

        items = SubscriptionItem.for_sponsors_listing(sponsors_listing.id)
        assert_includes items, active_subscription_item
        assert_includes items, retired_subscription_item
        refute_includes items, other_subscription_item
      end
    end

    context "#sponsors_fee" do
      test "fee amount is positive for CC org" do
        org = create(:credit_card_org)

        tier = create(:sponsors_tier, :approved_sponsors_listing)
        sponsorship = create(:sponsorship, sponsor: org, tier: tier)
        plan_sub = create(:billing_plan_subscription, user: org)
        subscription_item = build(:sponsors_subscription_item, plan_subscription: plan_sub, subscribable: tier, sponsorship: sponsorship)
        flat_price = Billing::Money.new(500)

        assert subscription_item.sponsors_fee(flat_price).positive?
      end

      test "fee amount is zero for non-org users" do
        user = create(:user)

        tier = create(:sponsors_tier, :approved_sponsors_listing)
        sponsorship = create(:sponsorship, sponsor: user, tier: tier)
        plan_sub = create(:billing_plan_subscription, user: user)
        subscription_item = build(:sponsors_subscription_item, plan_subscription: plan_sub, subscribable: tier, sponsorship: sponsorship)
        flat_price = Billing::Money.new(500)

        assert subscription_item.sponsors_fee(flat_price).zero?
      end

      test "fee amount is zero for invoiced orgs" do
        org = create(:credit_card_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)

        tier = create(:sponsors_tier, :approved_sponsors_listing)
        sponsorship = create(:sponsorship, sponsor: org, tier: tier)
        plan_sub = org.sponsors_plan_subscription
        subscription_item = build(:sponsors_subscription_item, plan_subscription: plan_sub, subscribable: tier, sponsorship: sponsorship)
        flat_price = Billing::Money.new(500)

        assert subscription_item.sponsors_fee(flat_price).zero?
      end
    end

    context "#tier_not_owned_by_sponsor" do
      test "disallows creating a subscription item for a sponsors tier you own" do
        tier = create(:sponsors_tier, :approved_sponsors_listing)
        sponsorable = tier.sponsorable
        plan_sub = create(:billing_plan_subscription, user: sponsorable)
        subscription_item = build(:sponsors_subscription_item, subscribable: tier, plan_subscription: plan_sub)

        refute_predicate subscription_item, :valid?
        assert_includes subscription_item.errors[:sponsor], "cannot sponsor themselves"
      end
    end

    context "#pending_sponsorship_activation?" do
      test "false if no pending subscription item change" do
        sub_item = create(:sponsors_subscription_item)

        refute_predicate sub_item, :pending_sponsorship_activation?
      end

      test "true if subscription item will be activated by pending change" do
        sub_item = create(:sponsorship, :pending_activation).subscription_item

        assert_predicate sub_item, :pending_sponsorship_activation?
      end

      test "false if subscription item will not be activated by pending change" do
        sponsorship = create(:sponsorship, :pending_activation)
        other_tier = create(:sponsors_tier, :published, sponsors_listing: sponsorship.sponsors_listing)

        inactive_sub_item = create(:sponsors_subscription_item, :cancelled,
          subscribable: other_tier,
          account: sponsorship.sponsor,
        )
        pending_sub_item = sponsorship.subscription_item

        assert_predicate pending_sub_item, :pending_sponsorship_activation?
        refute_predicate inactive_sub_item, :pending_sponsorship_activation?
      end
    end
  end
end
