# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class SubscriptionItemTest < GitHub::BillingTestCase
    fixtures do
      @business = create(:billing_plan_subscription, :business_owned).business
      @owner = @business.owners.first
      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
    end

    context "#managing_entity" do
      test "returns the subscription item's organization when it's set, even if account is also set" do
        org_admin = create(:user)
        org = create(:organization, admin: org_admin)
        sub_item = create(:billing_subscription_item, organization: org, account: org_admin)

        assert_equal org, sub_item.managing_entity
      end

      test "returns the subscription item's account when it's a user" do
        user = create(:user)
        sub_item = create(:billing_subscription_item, account: user, organization: nil)
        assert_equal user, sub_item.managing_entity
      end

      test "returns the subscription item's account when it's an organization" do
        org = create(:organization)
        sub_item = create(:billing_subscription_item, account: org, organization: nil)
        assert_equal org, sub_item.managing_entity
      end

      test "returns nil when the organization is not set and the account is a business" do
        business = create(:business, :with_self_serve_payment)
        plan_sub = create(:billing_plan_subscription, :business_owned, customer: business.customer)
        org = create(:organization, business: business, admin: business.owners.first)
        sub_item = create(:billing_subscription_item, plan_subscription: plan_sub, organization: nil)
        assert_equal business, sub_item.account, "need a business account"

        assert_nil sub_item.managing_entity
      end
    end

    context "#pending_subscription_item_change and #async_pending_subscription_item_change" do
      test "returns nil when there is no pending change for the subscription item" do
        listing_plan = create(:marketplace_listing_plan, :verified_listing)
        subscription_item = create(:billing_subscription_item, subscribable: listing_plan)

        assert_nil subscription_item.pending_subscription_item_change
        assert_nil subscription_item.async_pending_subscription_item_change.sync
      end

      test "returns the pending change for the subscription item" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create(:marketplace_listing_plan, listing: listing, state: :published)
        subscription_item = create(:billing_subscription_item, subscribable: listing_plan)

        assert_nil subscription_item.pending_subscription_item_change
        assert_nil subscription_item.async_pending_subscription_item_change.sync

        plan_sub = subscription_item.plan_subscription
        account = plan_sub.user
        plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 1.month, user: account)
        pending_sub_item_change = create(:billing_pending_subscription_item_change, :cancellation,
          subscribable: listing_plan, pending_plan_change: plan_change)

        assert_equal pending_sub_item_change, subscription_item.reload.pending_subscription_item_change
        assert_equal pending_sub_item_change, subscription_item.async_pending_subscription_item_change.sync
      end

      context "self-serve payment enterprise account orgs" do
        test "returns nil when there is no pending change for the marketplace subscription item for an org" do
          business = create :business, :with_self_serve_payment
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: business.customer
          business_admin = business.owners.first
          org = create :organization, business: business, admin: business_admin

          listing_plan = create(:marketplace_listing_plan, :verified_listing)
          subscription_item = create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription, organization: org)

          assert_nil subscription_item.pending_subscription_item_change
          assert_nil subscription_item.async_pending_subscription_item_change.sync
        end

        test "returns the pending change for the marketplace subscription item for an org" do
          business = create :business, :with_self_serve_payment
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: business.customer
          business_admin = business.owners.first
          org = create :organization, business: business, admin: business_admin

          listing = create(:marketplace_listing, :verified)
          listing_plan = create(:marketplace_listing_plan, listing: listing, state: :published)
          subscription_item = create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription, organization: org)

          assert_nil subscription_item.pending_subscription_item_change
          assert_nil subscription_item.async_pending_subscription_item_change.sync

          plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 1.month, user: nil, customer_id: business.customer.id)
          pending_sub_item_change = create(:billing_pending_subscription_item_change, :cancellation,
            subscribable: listing_plan, pending_plan_change: plan_change,
            plan_subscription: plan_subscription, organization: org)

          assert_equal pending_sub_item_change, subscription_item.reload.pending_subscription_item_change
          assert_equal pending_sub_item_change, subscription_item.async_pending_subscription_item_change.sync
        end

        test "returns nil when there is no pending change for the sponsors subscription item for an org" do
          sub_item = create(:sponsors_subscription_item, :self_serve_business)
          plan_sub = sub_item.plan_subscription
          subscribable = sub_item.subscribable
          business = sub_item.account

          other_member_org = create(:organization, business: business)
          other_member_org_sub_item = create(:sponsors_subscription_item,
            account: other_member_org,
            subscribable: subscribable
          )

          # create a similar pending sub item change for another member org to ensure we disambiguate
          plan_change = create(:billing_pending_plan_change,
            active_on: GitHub::Billing.today + 1.month,
            user: nil,
            customer: business.customer
          )
          other_member_org_pending_sub_item_change = create(:billing_pending_subscription_item_change, :cancellation,
            subscribable: subscribable, pending_plan_change: plan_change,
            plan_subscription: plan_sub, organization: other_member_org)

          assert_nil sub_item.pending_subscription_item_change
          assert_nil sub_item.async_pending_subscription_item_change.sync
        end

        test "returns the pending change for the sponsors subscription item for an org" do
          sub_item = create(:sponsors_subscription_item, :self_serve_business)
          plan_sub = sub_item.plan_subscription
          subscribable = sub_item.subscribable
          business = sub_item.account

          other_member_org = create(:organization, business: business)
          other_member_org_sub_item = create(:sponsors_subscription_item,
            account: other_member_org,
            subscribable: subscribable
          )

          # create a similar pending sub item change for another member org to ensure we disambiguate
          plan_change = create(:billing_pending_plan_change,
            active_on: GitHub::Billing.today + 1.month,
            user: nil,
            customer: business.customer
          )
          pending_sub_item_change = create(:billing_pending_subscription_item_change, :cancellation,
            subscribable: subscribable, pending_plan_change: plan_change,
            plan_subscription: plan_sub, organization: sub_item.organization)

          assert_nil other_member_org_sub_item.pending_subscription_item_change
          assert_nil other_member_org_sub_item.async_pending_subscription_item_change.sync
          assert_equal pending_sub_item_change, sub_item.reload.pending_subscription_item_change
          assert_equal pending_sub_item_change, sub_item.async_pending_subscription_item_change.sync
        end
      end
    end

    context "#subscribable_paid?" do
      test "returns true when subscribable price is non-zero" do
        tier = build(:sponsors_tier, :published, monthly_price_in_cents: 5_00)
        sub_item = build(:sponsors_subscription_item, subscribable: tier)
        assert_predicate sub_item, :subscribable_paid?
      end

      test "returns false when subscribable price is zero" do
        listing_plan = build(:marketplace_listing_plan, :free)
        sub_item = build(:sponsors_subscription_item, subscribable: listing_plan)
        refute_predicate sub_item, :subscribable_paid?
      end

      # https://github.com/github/sponsors/issues/5352#issuecomment-1786018555
      test "returns false when subscribable does not exist" do
        tier = create(:sponsors_tier, :published, monthly_price_in_cents: 5_00)
        sub_item = create(:sponsors_subscription_item, subscribable: tier)
        tier.delete
        refute_predicate sub_item.reload, :subscribable_paid?
      end
    end

    context "#subscribable_name" do
      # https://github.com/github/sponsors/issues/5352
      test "returns nil when subscribable no longer exists" do
        listing_plan = create(:marketplace_listing_plan, :verified_listing)
        sub_item = create(:billing_subscription_item, subscribable: listing_plan)
        listing_plan.delete

        assert_nil sub_item.reload.subscribable_name
      end

      test "returns the name of the subscribable" do
        name = "I like the nyckelharpa"
        listing_plan = create(:marketplace_listing_plan, :verified_listing, name: name)
        sub_item = create(:billing_subscription_item, subscribable: listing_plan)

        assert_equal name, sub_item.subscribable_name
      end
    end

    context "#async_subscribable_for_same_listing?" do
      test "resolves to true when given subscribable is tied to the same listing as the subscription item's subscribable" do
        listing = create(:sponsors_listing, :approved, tier_count: 2)
        subscribable1, subscribable2 = listing.published_sponsors_tiers.limit(2)
        sub_item = create(:sponsors_subscription_item, subscribable: subscribable1)

        assert sub_item.async_subscribable_for_same_listing?(subscribable2).sync
      end

      test "resolves to false when given nil" do
        sub_item = create(:billing_subscription_item)
        refute sub_item.async_subscribable_for_same_listing?(nil).sync
      end

      test "resolves to false when given a subscribable of a different type than what's on the subscription item" do
        sub_item = create(:sponsors_subscription_item)
        subscribable = create(:marketplace_listing_plan)
        refute sub_item.async_subscribable_for_same_listing?(subscribable).sync
      end

      test "resolves to false when given a subscribable for a different listing than what's on the subscription item" do
        subscribable1, subscribable2 = create_pair(:marketplace_listing_plan, :verified_listing)
        refute_equal subscribable1.listing, subscribable2.listing, "need subscribables from two different listings"
        sub_item = create(:billing_subscription_item, subscribable: subscribable1)
        refute sub_item.async_subscribable_for_same_listing?(subscribable2).sync
      end
    end

    context "without_product_uuid_type scope" do
      test "includes only subscription items whose subscribable is not a product UUID" do
        product_item = create(:billing_subscription_item, :with_product_uuid)
        marketplace_item = create(:billing_subscription_item, :free_trial)
        assert_predicate marketplace_item, :subscribable_Marketplace_ListingPlan?
        sponsors_item = create(:sponsors_subscription_item)

        result = Billing::SubscriptionItem.without_product_uuid_type
          .where(id: [product_item.id, marketplace_item.id, sponsors_item.id])

        assert_includes result, marketplace_item
        assert_includes result, sponsors_item
        refute_includes result, product_item
      end
    end

    context ".async_total_monthly_price_in_cents" do
      test "returns promise resolving to sum of given scope" do
        mkt_subscribable = create(:marketplace_listing_plan, :published,
          monthly_price_in_cents: 3_51)
        mkt_sub_item = create(:billing_subscription_item, subscribable: mkt_subscribable,
          quantity: 2)
        spon_subscribable = create(:sponsors_tier, :approved_sponsors_listing,
          monthly_price_in_cents: 10_00)
        spon_sub_item = create(:sponsors_subscription_item, subscribable: spon_subscribable)
        scope = Billing::SubscriptionItem.where(id: [mkt_sub_item, spon_sub_item])

        result = Billing::SubscriptionItem.async_total_monthly_price_in_cents(scope, include_fees: false).sync

        assert_equal 17_02, result
      end

      test "returns promise resolving to sum of given array" do
        mkt_subscribable = create(:marketplace_listing_plan, :published,
          monthly_price_in_cents: 3_51)
        mkt_sub_item = create(:billing_subscription_item, subscribable: mkt_subscribable,
          quantity: 2)
        spon_subscribable = create(:sponsors_tier, :approved_sponsors_listing,
          monthly_price_in_cents: 10_00)
        spon_sub_item = create(:sponsors_subscription_item, subscribable: spon_subscribable)
        list = [mkt_sub_item, spon_sub_item]

        result = Billing::SubscriptionItem.async_total_monthly_price_in_cents(list, include_fees: false).sync

        assert_equal 17_02, result
      end

      test "includes fees when include_fees is true" do
        org = create(:credit_card_organization)

        tier = create(:sponsors_tier, :approved_sponsors_listing,
          monthly_price_in_cents: 10_00)
        tier2 = create(:sponsors_tier, :approved_sponsors_listing,
          monthly_price_in_cents: 20_00)
        item = create(:sponsors_subscription_item, account: org, subscribable: tier)
        item2 = create(:sponsors_subscription_item, account: org, subscribable: tier2)
        list = [item, item2]

        result = Billing::SubscriptionItem.async_total_monthly_price_in_cents(list, include_fees: true).sync

        assert_equal 31_80, result # (10 + 20) + 6% fee
      end

      test "does not include fees when include_fees is false" do
        org = create(:credit_card_organization)

        tier = create(:sponsors_tier, :approved_sponsors_listing,
          monthly_price_in_cents: 10_00)
        tier2 = create(:sponsors_tier, :approved_sponsors_listing,
          monthly_price_in_cents: 20_00)
        item = create(:sponsors_subscription_item, account: org, subscribable: tier)
        item2 = create(:sponsors_subscription_item, account: org, subscribable: tier2)
        list = [item, item2]

        result = Billing::SubscriptionItem.async_total_monthly_price_in_cents(list, include_fees: false).sync

        assert_equal 30_00, result # 10 + 20
      end

      # https://github.com/github/sponsors/issues/5352
      test "handles when a subscribable does not exist and an array is given" do
        mkt_subscribable = create(:marketplace_listing_plan, :published,
          monthly_price_in_cents: 3_51)
        mkt_sub_item = create(:billing_subscription_item, subscribable: mkt_subscribable,
          quantity: 2)
        spon_subscribable = create(:sponsors_tier, :approved_sponsors_listing,
          monthly_price_in_cents: 10_00)
        spon_sub_item = create(:sponsors_subscription_item, subscribable: spon_subscribable)
        spon_subscribable.delete
        list = [mkt_sub_item, spon_sub_item.reload]

        result = Billing::SubscriptionItem.async_total_monthly_price_in_cents(list, include_fees: false).sync

        assert_equal 7_02, result
      end

      # https://github.com/github/sponsors/issues/5352
      test "handles when a subscribable does not exist and a scope is given" do
        mkt_subscribable = create(:marketplace_listing_plan, :published,
          monthly_price_in_cents: 3_51)
        mkt_sub_item = create(:billing_subscription_item, subscribable: mkt_subscribable,
          quantity: 2)
        spon_subscribable = create(:sponsors_tier, :approved_sponsors_listing,
          monthly_price_in_cents: 10_00)
        spon_sub_item = create(:sponsors_subscription_item, subscribable: spon_subscribable)
        spon_subscribable.delete
        scope = Billing::SubscriptionItem.where(id: [mkt_sub_item.id, spon_sub_item.id])

        result = Billing::SubscriptionItem.async_total_monthly_price_in_cents(scope, include_fees: false).sync

        assert_equal 7_02, result
      end
    end

    context "#pending_subscription_item_changes_for_product" do
      test "raises an expection for non ProductUUID subscribables" do
        # We could implement this method for other subscribables by accessing their ProductUUID
        # but for now, this method is only used by ProductUUID specific flows
        subscribable = create(:marketplace_listing_plan, :published)
        sub_item = create(:billing_subscription_item, subscribable: subscribable)

        assert_raises(NotImplementedError) do
          sub_item.pending_subscription_item_changes_for_product
        end
      end

      test "returns a list of pending subscription item changes for a product regardless of the billing cycle" do
        copilot_monthly_uuid = create(:billing_product_uuid, :copilot)
        copilot_yearly_uuid = create(:billing_product_uuid, :copilot, :yearly)

        sub_item = create(:billing_subscription_item, subscribable: copilot_monthly_uuid)
        account = sub_item.account
        plan_subscription = account.plan_subscription
        change = create(:billing_pending_plan_change, user: account)
        monthly_pending_change = create(
          :billing_pending_subscription_item_change,
          pending_plan_change: change,
          subscribable: sub_item.subscribable,
          plan_subscription: plan_subscription
        )
        yearly_pending_change = create(
          :billing_pending_subscription_item_change,
          pending_plan_change: change,
          subscribable: copilot_yearly_uuid,
          plan_subscription: plan_subscription
        )

        result = sub_item.pending_subscription_item_changes_for_product

        assert_equal 2, result.count
        assert_same_elements [monthly_pending_change, yearly_pending_change], result
      end
    end

    context "#on_free_trial?" do
      context "for product_uuids (e.g. copilot)" do
        test "returns true until end of day of free_trial_ends_on" do
          item = create :billing_subscription_item,
            subscribable: create(:billing_product_uuid, :copilot),
            quantity: 1,
            free_trial_ends_on: GitHub::Billing.today

          # Freeze time in the billing timezone end of day (i.e. Tue, 25 Oct 2022 23:59:59.999999999 PDT -07:00)
          # This is the last moment the trial is considered active
          Timecop.freeze(GitHub::Billing.now.end_of_day) do
            assert item.on_free_trial?
          end
        end

        test "returns false on the day after free_trial_ends_on" do
          item = create :billing_subscription_item,
            subscribable: create(:billing_product_uuid, :copilot),
            quantity: 1,
            free_trial_ends_on: GitHub::Billing.today

          # Freeze time in the beginning of the next day (i.e. Wed, 26 Oct 2022 00:00:00.000000000 PDT -07:00)
          # This is the first moment the trial is considered inactive
          Timecop.freeze(GitHub::Billing.now.beginning_of_day + 1.day) do
            refute item.on_free_trial?
          end
        end
      end

      context "for non-product_uuids (e.g. marketplace)" do
        test "returns true until end of day of free_trial_ends_on" do
          item = create :billing_subscription_item,
            subscribable: create(:marketplace_listing_plan, :verified_listing),
            quantity: 1,
            free_trial_ends_on: GitHub::Billing.today

          # Freeze time in the billing timezone end of day (i.e. Tue, 25 Oct 2022 23:59:59.999999999 PDT -07:00)
          # This is the last moment the trial is considered active
          Timecop.freeze(GitHub::Billing.now.end_of_day) do
            assert item.on_free_trial?
          end
        end

        test "returns false on the day after free_trial_ends_on" do
          item = create :billing_subscription_item,
            subscribable: create(:marketplace_listing_plan, :verified_listing),
            quantity: 1,
            free_trial_ends_on: GitHub::Billing.today

          # Freeze time in the beginning of the next day (i.e. Wed, 26 Oct 2022 00:00:00.000000000 PDT -07:00)
          # This is the first moment the trial is considered inactive
          Timecop.freeze(GitHub::Billing.now.beginning_of_day + 1.day) do
            refute item.on_free_trial?
          end
        end
      end
    end

    context "#disqualifies_for_free_trial?" do
      test "returns true if subscription item is paid" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create :marketplace_listing_plan,
          :published,
          listing: listing,
          monthly_price_in_cents: 3_51
        subscription_item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 2

        assert subscription_item.paid?
        assert subscription_item.disqualifies_for_free_trial?
      end

      test "returns true if subscription item is on free trial" do
        subscription_item = create(:billing_subscription_item, :free_trial)

        refute subscription_item.paid?
        assert subscription_item.on_free_trial?
        assert subscription_item.disqualifies_for_free_trial?
      end

      test "free subscription items don't disqualify for free trial" do
        subscription_item = create(:billing_subscription_item, :free)

        refute subscription_item.paid?
        refute subscription_item.on_free_trial?
        refute subscription_item.disqualifies_for_free_trial?
      end
    end

    context "#subscription_summary" do
      test "returns summary for a subscription item with a Sponsors tier subscribable" do
        tier = create(:sponsors_tier, :published, :one_time)
        sub_item = create(:sponsors_subscription_item, subscribable: tier)

        assert_equal "#{tier.sponsors_listing.name} - #{tier.name}", sub_item.subscription_summary
      end

      test "returns summary for a subscription item with a Marketplace listing plan subscribable" do
        listing_plan = create(:marketplace_listing_plan, :published)
        sub_item = create(:billing_subscription_item, subscribable: listing_plan)

        assert_equal "#{listing_plan.listing.name} - #{listing_plan.name}", sub_item.subscription_summary
      end
    end

    context "#adminable_by?" do
      test "true for org admin when account is an org" do
        item = create(:billing_subscription_item, :org)

        assert_predicate item.account, :organization?
        assert item.adminable_by?(item.account.admins.first)
      end

      test "false for billing manager of org when account is an org" do
        item = create(:billing_subscription_item, :org)

        assert_predicate item.account, :organization?

        billing_manager = create(:user)
        item.account.billing.add_manager(billing_manager, actor: item.account.admins.first)

        refute item.adminable_by?(billing_manager)
      end

      test "false for user who does not admin org account" do
        item = create(:billing_subscription_item, :org)

        assert_predicate item.account, :organization?
        refute item.adminable_by?(create(:user))
      end

      test "true for user when account is that user" do
        item = create :billing_subscription_item

        assert_predicate item.account, :user?
        assert item.adminable_by?(item.account)
      end

      test "false when given user is nil" do
        item = create :billing_subscription_item

        refute item.adminable_by?(nil)
      end

      test "false for different user than account user" do
        item = create :billing_subscription_item

        assert_predicate item.account, :user?
        refute item.adminable_by?(create(:user))
      end

      test "false when the subscription item does not have an account" do
        item = create :billing_subscription_item
        account = item.account

        item.update(plan_subscription: nil)

        assert_nil item.account
        refute item.adminable_by?(account)
      end
    end

    context ".create" do
      test "validates presence of quantity" do
        item = Billing::SubscriptionItem.new quantity: nil

        refute_predicate item, :valid?
        assert_includes item.errors[:quantity], "can't be blank"
      end

      test "validates numericality of quantity" do
        item = Billing::SubscriptionItem.new quantity: "dog"

        refute_predicate item, :valid?
        assert_includes item.errors[:quantity], "is not a number"
      end

      test "validates quantity is greater or equal to 0" do
        item = Billing::SubscriptionItem.new quantity: -1

        refute_predicate item, :valid?
        assert_includes item.errors[:quantity], "must be greater than or equal to 0"
      end

      test "validates quantity is less than or equal to 100,000" do
        item = Billing::SubscriptionItem.new quantity: 100_001

        refute_predicate item, :valid?
        assert_includes item.errors[:quantity], "must be less than or equal to 100000"
      end

      test "requires a plan subscription for an active subscription item on update" do
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 1_00
        item = create(:billing_subscription_item, subscribable: listing_plan, quantity: 1)

        item.plan_subscription = nil

        refute_predicate item, :valid?
        assert_includes item.errors[:plan_subscription], "can't be blank"
      end

      test "does not require a plan subscription for an inactive subscription item on update" do
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 1_00
        item = create(:billing_subscription_item, subscribable: listing_plan, quantity: 1)

        item.quantity = 0
        item.plan_subscription = nil

        assert_predicate item, :valid?
      end

      test "requires a plan subscription on create" do
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 1_00
        item = Billing::SubscriptionItem.new subscribable: listing_plan, quantity: 0

        refute_predicate item, :valid?
        assert_includes item.errors[:plan_subscription], "can't be blank"
      end

      test "requires a subscribable" do
        plan_subscription = create :billing_plan_subscription
        item              = Billing::SubscriptionItem.new plan_subscription: plan_subscription

        refute_predicate item, :valid?
        assert_includes item.errors[:subscribable_id], "can't be blank"
      end

      test "requires a valid listing plan" do
        plan = create :marketplace_listing_plan, :retired
        item = Billing::SubscriptionItem.new subscribable: plan

        refute_predicate item, :valid?
        assert_includes item.errors[:base], "can't have a retired listing plan"
      end

      test "a user can only have one Marketplace listing plan per Marketplace listing" do
        user = create :credit_card_user, plan: "small"
        plan_subscription = create(:billing_plan_subscription, user: user)
        user.reload
        old_item = create :billing_subscription_item, plan_subscription: plan_subscription

        listing_plan = create :marketplace_listing_plan,
          :published, listing: old_item.listing

        item = Billing::SubscriptionItem.new \
          plan_subscription: user.plan_subscription,
          subscribable: listing_plan,
          quantity: 1

        refute item.save
        assert_includes item.errors[:base], "already has an active subscription for #{old_item.subscribable_name}"
      end

      test "a user can have an active subscription for plans from two different Marketplace listings" do
        plan1 = create(:marketplace_listing_plan, :published)
        plan2 = create(:marketplace_listing_plan, :published)
        refute_equal plan1.listing, plan2.listing
        sub_item1 = create(:billing_subscription_item, subscribable: plan1, quantity: 1)
        plan_subscription = sub_item1.plan_subscription

        sub_item2 = build(:billing_subscription_item, plan_subscription: plan_subscription, subscribable: plan2,
          quantity: 1)

        assert_predicate sub_item2, :valid?
      end

      test "a user can only have one subscription for a recurring tier per Sponsors listing" do
        listing = create(:sponsors_listing, :approved, tier_count: 2)
        tier1, tier2 = listing.published_sponsors_tiers
        sponsorship1 = create(:sponsorship, tier: tier1)
        sponsor = sponsorship1.sponsor

        sub_item = build(:sponsors_subscription_item, plan_subscription: sponsorship1.plan_subscription,
          subscribable: tier2, quantity: 1)

        refute_predicate sub_item, :valid?
        assert_includes sub_item.errors[:base], "already has an active subscription for #{tier1.name}"
      end

      test "a user can have an active subscription for tiers from two different Sponsors listings" do
        listing1 = create(:sponsors_listing, :approved)
        listing2 = create(:sponsors_listing, :approved)
        sponsorship1 = create(:sponsorship, tier: listing1.default_tier)
        sponsor = sponsorship1.sponsor
        plan_subscription = sponsorship1.plan_subscription

        sub_item = build(:sponsors_subscription_item, plan_subscription: plan_subscription,
          subscribable: listing2.default_tier, quantity: 1)

        assert_predicate sub_item, :valid?
      end

      test "a user can create a subscription for a one-time tier when they already have a subscription for a recurring tier for a Sponsors listing" do
        listing = create(:sponsors_listing, :approved, tier_count: 1, one_time_tier_count: 1)
        recurring_tier = listing.published_sponsors_tiers.recurring.first
        sponsorship = create(:sponsorship, tier: recurring_tier)
        plan_subscription = sponsorship.plan_subscription
        sponsor = sponsorship.sponsor
        one_time_tier = listing.published_sponsors_tiers.one_time.first

        sub_item = build(:sponsors_subscription_item, plan_subscription: plan_subscription,
          subscribable: one_time_tier, quantity: 1)

        assert_predicate sub_item, :valid?
      end

      test "a user can create a subscription for a recurring tier when they already have a subscription for a one-time tier for a Sponsors listing" do
        listing = create(:sponsors_listing, :approved, tier_count: 1, one_time_tier_count: 1)
        sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription))
        one_time_tier = listing.published_sponsors_tiers.one_time.first
        recurring_tier = listing.published_sponsors_tiers.recurring.first
        create(:sponsors_subscription_item, account: sponsor,
          subscribable: one_time_tier, quantity: 1)

        sub_item = create(:sponsors_subscription_item, account: sponsor,
          subscribable: recurring_tier, quantity: 1)

        assert_predicate sub_item, :valid?
      end

      test "a user cannot have two active subscriptions for two one-time tiers at the same time for a Sponsors listing" do
        listing = create(:sponsors_listing, :approved, tier_count: 0, one_time_tier_count: 2)
        one_time_tier1, one_time_tier2 = listing.published_sponsors_tiers.one_time
        sponsorship = create(:sponsorship, tier: one_time_tier1)
        sponsor = sponsorship.sponsor

        sub_item = build(:sponsors_subscription_item, plan_subscription: sponsorship.plan_subscription,
          subscribable: one_time_tier2, quantity: 1)

        refute_predicate sub_item, :valid?
        assert_includes sub_item.errors[:base], "already has an active subscription for #{one_time_tier1.name}"
      end

      test "allows creation of subscription of sponsors listing that shares id with unrelated marketplace listing" do
        sponsorable = create(:user, :verified)
        sponsor = create(:credit_card_user, plan: GitHub::Plan.free_with_addons)
        plan_subscription = create(:billing_plan_subscription, user: sponsor)
        marketplace_listing = create(:marketplace_listing, :with_plans)
        sponsors_listing = create(:sponsors_listing, :with_tier,
          id: marketplace_listing.id,
          sponsorable: sponsorable
        )
        create(:billing_subscription_item,
          plan_subscription: plan_subscription,
          subscribable: marketplace_listing.default_plan,
        )

        # make sure we're up to date with what items have been created
        sponsor.reload
        plan_subscription.reload

        assert_equal 1, plan_subscription.active_subscription_items.count
        assert_equal sponsors_listing.id, plan_subscription.active_subscription_items.first.listing.id

        item = create(:sponsors_subscription_item,
          account: sponsor,
          subscribable: sponsors_listing.default_tier,
        )

        assert_predicate item, :valid?
      end

      test "User accounts cannot subscribe to a Org only listing plan" do
        listing_plan = create :marketplace_listing_plan, :published, :organizations_only

        user = create :credit_card_user, plan_duration: "month"
        plan_subscription = create :billing_plan_subscription, user: user
        item = Billing::SubscriptionItem.new \
          plan_subscription: plan_subscription,
          subscribable: listing_plan,
          quantity: 1

        refute_predicate item, :valid?
        assert_includes item.errors[:base], "This plan is for organizations only, please select a different billing account or plan."
      end

      test "Org accounts cannot subscribe to a User only listing plan" do
        listing_plan = create :marketplace_listing_plan, :published, :users_only
        plan_subscription = create :billing_plan_subscription, :org
        item = Billing::SubscriptionItem.new \
          plan_subscription: plan_subscription,
          subscribable: listing_plan,
          quantity: 1

        refute_predicate item, :valid?
        assert_includes item.errors[:base], "This plan is for personal accounts only, please select a different billing account or plan."
      end

      test "can have multiple plans per listing if others are cancelled" do
        item = create :billing_subscription_item, quantity: 0

        listing_plan = create :marketplace_listing_plan, :published, listing: item.listing

        item = Billing::SubscriptionItem.new \
          plan_subscription: item.plan_subscription,
          subscribable: listing_plan,
          quantity: 1

        assert item.save
      end

      test "can save a cancelled listing" do
        item = create :billing_subscription_item, quantity: 10

        listing_plan = create :marketplace_listing_plan, :published, listing: item.listing

        item = Billing::SubscriptionItem.new \
          plan_subscription: item.plan_subscription,
          subscribable: listing_plan,
          quantity: 0

        assert item.save
      end

      test "activating requires a specific plan subscription" do
        sponsors_sub_item = create(:sponsors_subscription_item, quantity: 0)
        other_sub_item = create(:billing_subscription_item, quantity: 0)

        sponsors_sub_item.quantity = 1
        other_sub_item.quantity = 1

        assert_predicate sponsors_sub_item, :valid?
        assert_predicate other_sub_item, :valid?

        sponsors_sub_item.plan_subscription.update!(purpose: :general)
        other_sub_item.plan_subscription.update!(purpose: :sponsors)

        refute_predicate sponsors_sub_item, :valid?
        assert_equal("Sponsorships can only be added to the sponsors-purpose subscription, please select a " \
          "different plan subscription.",
          sponsors_sub_item.errors[:subscribable].first
        )
        refute_predicate other_sub_item, :valid?
        assert_equal("Only sponsorships can be added to the sponsors-purpose subscription, please select a " \
          "different plan subscription.",
          other_sub_item.errors[:subscribable].first
        )
      end

      test "activating requires a specific plan subscription for a business" do
        plan_sub = create(:billing_plan_subscription, :business_owned)
        sponsors_plan_sub = create(:billing_plan_subscription, :business_owned, purpose: :sponsors)

        assert_predicate plan_sub, :billable_business?
        assert_predicate sponsors_plan_sub, :billable_business?

        sponsors_sub_item = create(:sponsors_subscription_item, plan_subscription: sponsors_plan_sub, quantity: 0)
        other_sub_item = create(:billing_subscription_item, plan_subscription: plan_sub, quantity: 0)

        sponsors_sub_item.quantity = 1
        other_sub_item.quantity = 1

        assert_predicate sponsors_sub_item, :valid?
        assert_predicate other_sub_item, :valid?

        sponsors_sub_item.plan_subscription.update!(purpose: :general)
        other_sub_item.plan_subscription.update!(purpose: :sponsors)

        refute_predicate sponsors_sub_item, :valid?
        assert_equal("Sponsorships can only be added to the sponsors-purpose subscription, please select a " \
          "different plan subscription.",
          sponsors_sub_item.errors[:subscribable].first
        )
        refute_predicate other_sub_item, :valid?
        assert_equal("Only sponsorships can be added to the sponsors-purpose subscription, please select a " \
          "different plan subscription.",
          other_sub_item.errors[:subscribable].first
        )
      end

      context "self-serve payment enterprise account orgs" do
        test "an org can only have one Marketplace listing plan per Marketplace listing" do
          org = create :organization, business: @business, admin: @owner
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: @business.customer
          old_item = create :billing_subscription_item, plan_subscription: plan_subscription, organization: org

          listing_plan = create :marketplace_listing_plan,
            :published, listing: old_item.listing

          item = Billing::SubscriptionItem.new \
            plan_subscription: plan_subscription,
            subscribable: listing_plan,
            quantity: 1,
            organization: org

          refute item.save
          assert_includes item.errors[:base], "already has an active subscription for #{old_item.subscribable_name}"
        end

        test "an org can have an active subscription for plans from two different Marketplace listings" do
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: @business.customer
          plan1 = create(:marketplace_listing_plan, :published)
          plan2 = create(:marketplace_listing_plan, :published)
          refute_equal plan1.listing, plan2.listing
          org = create :organization, business: @business, admin: @owner

          sub_item1 = create(:billing_subscription_item, subscribable: plan1, plan_subscription: plan_subscription,
            quantity: 1, organization: org)
          sub_item2 = build(:billing_subscription_item, subscribable: plan2, plan_subscription: plan_subscription,
            quantity: 1, organization: org)

          assert_predicate sub_item2, :valid?
        end

        test "two orgs can have active subscription for plans from the same Marketplace listing" do
          plan = create(:marketplace_listing_plan, :published)
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: @business.customer
          org1 = create :organization, business: @business, admin: @owner
          org2 = create :organization, business: @business, admin: @owner

          sub_item1 = create(:billing_subscription_item, subscribable: plan, plan_subscription: plan_subscription,
            quantity: 1, organization: org1)
          sub_item2 = build(:billing_subscription_item, subscribable: plan, plan_subscription: plan_subscription,
            quantity: 1, organization: org2)

          assert_predicate sub_item2, :valid?
        end

        test "two member orgs can have active subscriptions for the same Sponsors tier" do
          sub_item1 = create(:sponsors_subscription_item, :self_serve_business)
          business = sub_item1.account
          other_member_org = create(:organization, business: business)
          sub_item2 = create(:sponsors_subscription_item,
            account: other_member_org,
            subscribable: sub_item1.sponsors_tier
          )

          assert_equal sub_item1.subscribable, sub_item2.subscribable

          assert_predicate sub_item2, :valid?
        end
      end
    end

    context "#can_be_concurrent_with_subscription_item_for?" do
      test "true for a subscription item without a subscribable" do
        sub_item = create(:billing_subscription_item, quantity: 1)
        other_subscribable = create(:marketplace_listing_plan, :published, listing: sub_item.listing)
        sub_item.subscribable.delete

        assert sub_item.reload.can_be_concurrent_with_subscription_item_for?(other_subscribable)
      end

      test "true for an inactive subscription item" do
        sub_item = create(:billing_subscription_item, quantity: 0)
        other_subscribable = create(:marketplace_listing_plan, :published, listing: sub_item.listing)

        assert sub_item.can_be_concurrent_with_subscription_item_for?(other_subscribable)
      end

      test "true when the subscription item's subscribable allows it" do
        sub_item = create(:billing_subscription_item, quantity: 1)
        other_subscribable = create(:marketplace_listing_plan, :published, listing: sub_item.listing)
        sub_item.subscribable.stubs(:can_be_concurrent_with_subscription_item_for?).returns(true)

        assert sub_item.can_be_concurrent_with_subscription_item_for?(other_subscribable)
      end

      test "false when the subscription item's subscribable does not allow it" do
        sub_item = create(:billing_subscription_item, quantity: 1)
        other_subscribable = create(:marketplace_listing_plan, :published, listing: sub_item.listing)
        sub_item.subscribable.stubs(:can_be_concurrent_with_subscription_item_for?).returns(false)

        refute sub_item.can_be_concurrent_with_subscription_item_for?(other_subscribable)
      end
    end

    context "#billing_interval" do
      test "returns billing cycle if subscribable is a ProductUUID" do
        sub_item = create(:billing_subscription_item, :with_product_uuid)
        assert_equal sub_item.subscribable.billing_cycle, sub_item.billing_interval
      end

      test "returns user's plan duration" do
        user = create(:credit_card_user, plan_duration: "month")
        plan_subscription = create(:billing_plan_subscription, user: user)
        sub_item = create(:billing_subscription_item, plan_subscription: plan_subscription)

        assert_equal user.plan_duration, sub_item.billing_interval
      end

      test "returns business' plan duration" do
        plan_subscription = create(:billing_plan_subscription, :business_owned)
        sub_item = create(:billing_subscription_item, plan_subscription: plan_subscription)

        assert_equal plan_subscription.business.plan_duration, sub_item.billing_interval
      end

      test "returns nil when the subscription item does not have a billable entity" do
        user = create(:credit_card_user, :verified)
        plan_sub = create(:billing_plan_subscription, :zuora, user: user)
        sub_item = create(:billing_subscription_item, plan_subscription: plan_sub)
        plan_sub.delete
        sub_item.reload

        assert_nil sub_item.billing_interval
      end

      test "can be batch loaded" do
        user = create(:credit_card_user, plan_duration: "month")
        user_plan_subscription = create(:billing_plan_subscription, user: user)
        business_plan_subscription = create(:billing_plan_subscription, :business_owned)

        product_uuid_sub_item = create(:billing_subscription_item, :with_product_uuid)
        user_sub_item = create(:billing_subscription_item, plan_subscription: user_plan_subscription)
        business_sub_item = create(:billing_subscription_item, plan_subscription: business_plan_subscription)

        GitHub::PrefillAssociations.prefill_batch_method(
          [product_uuid_sub_item, user_sub_item, business_sub_item],
          :billing_interval
        )

        assert_query_count(0) do
          assert_equal product_uuid_sub_item.subscribable.billing_cycle, product_uuid_sub_item.billing_interval
          assert_equal user.plan_duration, user_sub_item.billing_interval
          assert_equal business_plan_subscription.business.plan_duration, business_sub_item.billing_interval
        end
      end
    end

    context "#price and #async_price" do
      test "returns addon price when user has paid item on free trial listing plan" do
        listing_plan = create :marketplace_listing_plan, :published
        user = create :credit_card_user, plan_duration: "month"
        plan_subscription = create :billing_plan_subscription, user: user
        item = create :billing_subscription_item,
          quantity: 1,
          subscribable: listing_plan,
          plan_subscription: plan_subscription
        listing_plan.update!(has_free_trial: true)
        expected = Billing::Money.new(listing_plan.monthly_price_in_cents)

        assert_equal expected, item.price
        assert_equal expected, item.async_price.sync
      end

      test "returns monthly price for quantity" do
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 1_00
        user = create :credit_card_user, plan_duration: "month"
        plan_subscription = create :billing_plan_subscription, user: user
        item = create :billing_subscription_item,
          quantity: 2,
          subscribable: listing_plan,
          plan_subscription: plan_subscription

        assert_money 2_00, item.price
        assert_money 2_00, item.async_price.sync
      end

      test "returns yearly price for quantity" do
        listing_plan = create :marketplace_listing_plan,
          :published, yearly_price_in_cents: 1_00

        user = create :credit_card_user, plan_duration: "year"
        plan_subscription = create :billing_plan_subscription, user: user

        item = create :billing_subscription_item,
          quantity: 2,
          subscribable: listing_plan,
          plan_subscription: plan_subscription

        assert_money 2_00, item.price
        assert_money 2_00, item.async_price.sync
      end

      test "defaults to monthly pricing" do
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 1_00, yearly_price_in_cents: 10_00

        item = Billing::SubscriptionItem.new \
          quantity: 2,
          subscribable: listing_plan

        assert_money 2_00, item.price
        assert_money 2_00, item.async_price.sync
      end

      test "returns $0 cost when plan has a free trial" do
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 1_00, has_free_trial: true
        item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 2

        assert_money 0, item.price
        assert_money 0, item.async_price.sync
      end

      test "returns price when plan does not have free trial even with trial discount enabled" do
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 1_00, has_free_trial: false
        item = create(:billing_subscription_item, subscribable: listing_plan, quantity: 2)
        account = item.account
        item = Billing::SubscriptionItem.new \
          subscribable: listing_plan,
          quantity: 2,
          plan_subscription: account.plan_subscription

        assert_money 2_00, item.price
        assert_money 2_00, item.async_price.sync
      end

      test "returns price without trial discount when trial_price is false" do
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 1_00, has_free_trial: true
        item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 2

        assert_money 2_00, item.price(trial_price: false)
        assert_money 2_00, item.async_price(trial_price: false).sync
      end

      test "returns prorated price when mid billing cycle" do
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 3_51
        subscription_item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 2

        assert_equal 1_75, subscription_item.price(duration: :month, service_remaining: 0.25).cents
        assert_equal 1_75, subscription_item.async_price(duration: :month, service_remaining: 0.25).sync.cents
      end

      # https://github.com/github/sponsors/issues/5352
      test "handles when subscribable no longer exists" do
        sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing, monthly_price_in_cents: 5_00)
        sub_item = create(:sponsors_subscription_item, subscribable: sponsors_tier)
        sponsors_tier.delete

        assert_equal Billing::Money.zero, sub_item.reload.price
        assert_equal Billing::Money.zero, sub_item.async_price.sync
      end
    end

    context "#billable?" do
      test "returns true if paid and has a positive quantity for product UUID subscribables" do
        copilot_uuid = create(:billing_product_uuid, :copilot)
        subscription_item = create :billing_subscription_item,
          subscribable: copilot_uuid,
          quantity: 1

        assert subscription_item.billable?, "is a billable item"
      end

      test "returns false with a negative quantity for product UUID subscribables" do
        copilot_uuid = create(:billing_product_uuid, :copilot)
        subscription_item = create :billing_subscription_item,
          subscribable: copilot_uuid,
          quantity: 0

        refute subscription_item.billable?, "with a negative quantity should not be billable"
      end

      test "returns true if approved and paid and has a quantity" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create :marketplace_listing_plan,
          :published,
          listing: listing,
          monthly_price_in_cents: 3_51
        subscription_item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 2

        assert subscription_item.billable?, "is a billable item"
      end

      test "returns true for recent one-time sponsorship" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)
        sponsorship = create(:sponsorship, tier: tier)
        item = sponsorship.subscription_item

        assert_predicate item, :billable?
      end

      test "returns false for old one-time subscription item" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        one_time_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)

        not_recent_enough = (Billing::SubscriptionItem::SponsorsDependency::ONE_TIME_STALE_THRESHOLD + 1.minute).ago
        subscription_item = travel_to not_recent_enough do
          create(:sponsors_subscription_item, subscribable: one_time_tier)
        end

        refute_predicate subscription_item, :billable?
      end

      test "returns false if not approved" do
        listing = create(:marketplace_listing, :verification_pending_from_draft)
        listing_plan = create :marketplace_listing_plan,
          :published,
          listing: listing,
          monthly_price_in_cents: 3_51
        subscription_item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 2

        refute_predicate subscription_item, :billable?, "is not a billable item if not approved"
      end

      test "returns false if not paid" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create :marketplace_listing_plan,
          :published,
          listing: listing,
          monthly_price_in_cents: 0,
          yearly_price_in_cents: 0
        subscription_item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 2

        refute subscription_item.billable?, "is not a billable item if a free item"
      end

      test "returns false if on a free trial" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create :marketplace_listing_plan,
          :published,
          listing: listing,
          monthly_price_in_cents: 1_00,
          yearly_price_in_cents: 1_00,
          has_free_trial: true
        subscription_item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 2

        refute subscription_item.billable?, "is not a billable item if on a free trial"
      end

      test "returns false if there is no quantity" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create :marketplace_listing_plan,
          :published,
          listing: listing,
          monthly_price_in_cents: 10_00
        subscription_item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 0

        refute subscription_item.billable?, "is not a billable item if there is no quantity"
      end

      test "returns true for delisted listings" do
        listing = create(:marketplace_listing, :archived)
        listing_plan = create :marketplace_listing_plan,
          :published,
          listing: listing,
          monthly_price_in_cents: 3_51
        subscription_item = create :billing_subscription_item,
          subscribable: listing_plan,
          quantity: 2

        assert subscription_item.billable?, "is a billable item"
      end
    end

    context ".free_trials" do
      test "returns all free trials that have not yet ended" do
        Timecop.freeze(GitHub::Billing.timezone.parse("October 25 2017")) do
          current_free_trial = create(:billing_subscription_item, :free_trial)
          past_free_trial = create(:billing_subscription_item, :free_trial)
          past_free_trial.update_attribute(:free_trial_ends_on, 1.week.ago)

          assert_equal [current_free_trial], SubscriptionItem.free_trials
        end
      end
    end

    context "#next_billing_date" do
      context "for product_uuids" do
        test "returns the day after the free trial ends if there is a free trial" do
          freeze_time do
            free_trial_end_date = GitHub::Billing.today + 30.days
            copilot_product_uuid = create :billing_product_uuid, :copilot
            item = create :billing_subscription_item,
              subscribable: copilot_product_uuid,
              quantity: 1,
              free_trial_ends_on: free_trial_end_date

            assert_equal free_trial_end_date + 1.day, item.next_billing_date
          end
        end

        test "returns the current date when the item is not on free trial and has no external subscription" do
          freeze_time do
            copilot_product_uuid = create :billing_product_uuid, :copilot
            item = create :billing_subscription_item,
              subscribable: copilot_product_uuid,
              quantity: 1

            assert_equal GitHub::Billing.today, item.next_billing_date
          end
        end

        test "returns the charge_through_date from the zuora subscription from cache" do
          rate_plan_charge = attributes_for(:zuora_rate_plan_charge)
          charge_id = rate_plan_charge[:productRatePlanChargeId]
          next_billing_date = rate_plan_charge[:chargedThroughDate]

          plan_subscription = create :billing_plan_subscription, zuora_rate_plan_charges: {
            charge_id => {
              number: rate_plan_charge[:number],
              charged_through_date: Date.parse(next_billing_date)
            }
          }
          create(:plan_subscription_zuora_rate_plan_charge, plan_subscription: plan_subscription, payload: rate_plan_charge)

          plan_subscription.expects(:external_subscription).never

          copilot_product_uuid = create :billing_product_uuid,
            :copilot,
            zuora_product_rate_plan_charge_ids: { flat: charge_id }
          item = create :billing_subscription_item,
            plan_subscription: plan_subscription,
            subscribable: copilot_product_uuid,
            quantity: 1

          assert_equal Date.parse(next_billing_date), item.next_billing_date
        end

        test "updates the cache from the external subscription if the feature flag is enabled" do
          GitHub.flipper[:subscription_cache_always_update].enable
          GitHub.flipper[:new_zuora_rate_plan_charges].enable
          rate_plan_charge = attributes_for(:zuora_rate_plan_charge)
          charge_id = rate_plan_charge[:productRatePlanChargeId]
          next_billing_date = rate_plan_charge[:chargedThroughDate]

          plan_subscription = create :billing_plan_subscription, zuora_rate_plan_charges: {}

          raw_zuora_sub = attributes_for(:zuora_subscription, :active, ratePlans: [{
            ratePlanCharges: [rate_plan_charge],
          }])

          GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_zuora_sub)
          zuora_subscription = Billing::Zuora::Subscription.find("test")

          plan_subscription.stubs(:external_subscription).returns(zuora_subscription)

          copilot_product_uuid = create :billing_product_uuid,
            :copilot,
            zuora_product_rate_plan_charge_ids: { flat: charge_id }
          item = create :billing_subscription_item,
            plan_subscription: plan_subscription,
            subscribable: copilot_product_uuid,
            quantity: 1

          parsed_date = Date.parse(next_billing_date)
          assert_equal parsed_date, item.next_billing_date
          assert_equal parsed_date, plan_subscription.zuora_rate_plan_charges.dig(charge_id, :charged_through_date)
        end

      end
    end

    context "#destroy" do
      test "cleans up associated pending plan changes" do
        item = create :billing_subscription_item
        change = create :billing_pending_plan_change, user: item.user
        create :billing_pending_subscription_item_change,
          pending_plan_change: change,
          subscribable: item.subscribable

        assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
          item.destroy
        end
      end

      test "cleans up associated sponsorships" do
        sponsorable = create(:user, :sponsorable)
        sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription), plan: GitHub::Plan.free_with_addons)
        sponsorship = create(:sponsorship, sponsorable: sponsorable, sponsor: sponsor)
        item = sponsorship.subscription_item

        assert_difference "Sponsorship.count", -1 do
          item.destroy
        end
      end

      test "cleans up pending item changes for the specific product uuid associated to the subscription item" do
        monthly_product_uuid = create :billing_product_uuid, :copilot
        item_to_destroy = create :billing_subscription_item, subscribable: monthly_product_uuid
        change_to_destroy = create :billing_pending_subscription_item_change,
          subscribable: monthly_product_uuid,
          account: item_to_destroy.user
        yearly_product_uuid = create :billing_product_uuid, :copilot, :yearly
        create :billing_subscription_item, subscribable: yearly_product_uuid
        remaining_change = create :billing_pending_subscription_item_change,
          subscribable: yearly_product_uuid,
          account: item_to_destroy.user

        assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
          item_to_destroy.destroy
        end

        refute Billing::PendingSubscriptionItemChange.exists?(id: change_to_destroy.id)
        assert Billing::PendingSubscriptionItemChange.exists?(id: remaining_change.id)
      end

      test "does not error if user is nil" do
        item = create :billing_subscription_item
        change = create :billing_pending_plan_change, user: item.user
        create :billing_pending_subscription_item_change,
          pending_plan_change: change,
          subscribable: item.subscribable

        item.plan_subscription.update_columns(user_id: nil) # not null, but orphaned

        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          item.destroy
        end
      end
    end

    test "sets the free_trial_ends_on if lisiting plan has a free trial" do
      listing_plan = create :marketplace_listing_plan,
        :published, monthly_price_in_cents: 1_00, has_free_trial: true
      item = create :billing_subscription_item,
        subscribable: listing_plan,
        quantity: 2

      assert_money 0, item.price
      assert_equal GitHub::Billing.today + 14.days, item.free_trial_ends_on
    end

    test "does not set the free_trial_ends_on if the account is not eligible" do
      listing_plan = create :marketplace_listing_plan,
        :published, monthly_price_in_cents: 1_00, has_free_trial: true
      item = create :billing_subscription_item,
        subscribable: listing_plan,
        quantity: 2

      assert_money 0, item.price
      assert_equal GitHub::Billing.today + 14.days, item.free_trial_ends_on

      new_listing_plan = create :marketplace_listing_plan,
        :published, monthly_price_in_cents: 1_00, has_free_trial: true, listing: listing_plan.listing
      user = item.user.reload
      user.pending_plan_changes.destroy_all
      item.update!(quantity: 0, free_trial_ends_on: GitHub::Billing.today)
      new_item = create(:billing_subscription_item, plan_subscription: user.plan_subscription, subscribable: new_listing_plan, quantity: 1)

      assert_money listing_plan.monthly_price_in_cents, new_item.price
      assert_nil new_item.free_trial_ends_on
    end

    context "#reactivate!" do
      test "reactivates a cancelled subscription" do
        copilot_product_uuid = create(:billing_product_uuid, :copilot)
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        subscription_item = create(:billing_subscription_item, :iap, subscribable: copilot_product_uuid, plan_subscription:, quantity: 0)
        assert subscription_item.cancelled?

        result = subscription_item.reactivate!.result

        assert result.success
        subscription_item.reload
        refute subscription_item.cancelled?
      end

      test "extends a trial subscription, if the flag is passed" do
        copilot_product_uuid = create(:billing_product_uuid, :copilot)
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        subscription_item = create(:billing_subscription_item, :iap, subscribable: copilot_product_uuid, free_trial_ends_on: 10.days.from_now, plan_subscription:, quantity: 0)
        assert subscription_item.cancelled?

        result = subscription_item.reactivate!(free_trial_length: 30.days).result

        assert result.success
        subscription_item.reload
        refute subscription_item.cancelled?
        assert subscription_item.on_free_trial?
      end

      test "does not reactivate a one-time Sponsors payment" do
        listing = create(:sponsors_listing, :approved, tier_count: 1, one_time_tier_count: 1)
        recurring_tier = listing.published_sponsors_tiers.recurring.first
        sponsorship = create(:sponsorship, tier: recurring_tier)
        plan_subscription = sponsorship.plan_subscription
        one_time_tier = listing.published_sponsors_tiers.one_time.first

        sub_item = create(:sponsors_subscription_item, plan_subscription: plan_subscription,
          subscribable: one_time_tier, quantity: 0)

        assert sub_item.cancelled?

        result = sub_item.reactivate!.result


        refute result.success
        assert_includes_match /Cannot reactivate one-time sponsorship/, result.errors
      end

      test "does not reactivate or change the free trial length if the account is locked" do
        copilot_product_uuid = create(:billing_product_uuid, :copilot)
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        user.update(disabled: true)
        subscription_item = create(:billing_subscription_item, subscribable: copilot_product_uuid, plan_subscription:, quantity: 0, free_trial_ends_on: GitHub::Billing.today)

        assert subscription_item.cancelled?
        assert user.disabled?

        assert_raises ::Platform::Errors::Unprocessable do
          subscription_item.reactivate!(free_trial_length: 30.days).result
        end

        subscription_item.reload
        assert subscription_item.cancelled?
        assert GitHub::Billing.today, subscription_item.free_trial_ends_on
      end
    end

    context "#cancel!" do
      test "prevents cancelling IAP subscriptions" do
        copilot_product_uuid = create(:billing_product_uuid, :copilot)
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        subscription_item = create(:billing_subscription_item, :iap, subscribable: copilot_product_uuid, plan_subscription:)

        # Ensure data is staged correctly
        assert subscription_item.apple_subscription

        result = subscription_item.cancel!(force: true).result

        refute result.success
        assert_includes_match /Cannot cancel IAP subscription without explicitly overriding it./, result.errors
      end

      test "allows cancelling IAP subscriptions and destroys associated in-app purchase record if override provided" do
        copilot_product_uuid = create(:billing_product_uuid, :copilot)
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        subscription_item = create(:billing_subscription_item, :iap, subscribable: copilot_product_uuid, plan_subscription:)

        # Ensure data is staged correctly
        assert subscription_item.apple_subscription

        result = subscription_item.cancel!(force: true, allow_cancelling_iap: true).result

        assert result.success
        assert_nil subscription_item.reload.apple_subscription
      end

      test "cancels one-time Sponsors payment when concurrent recurring sponsorship exists" do
        listing = create(:sponsors_listing, :approved, tier_count: 1, one_time_tier_count: 1)
        recurring_tier = listing.published_sponsors_tiers.recurring.first
        sponsorship = create(:sponsorship, tier: recurring_tier)
        sponsor = sponsorship.sponsor
        plan_subscription = sponsorship.plan_subscription
        one_time_tier = listing.published_sponsors_tiers.one_time.first

        sub_item = create(:sponsors_subscription_item, plan_subscription: plan_subscription,
          subscribable: one_time_tier, quantity: 1)

        refute_predicate sub_item, :cancelled?

        result = sub_item.cancel!.result

        assert result.success
        assert_predicate sub_item.reload, :cancelled?
      end

      test "cancels pending subscription item changes when a product uuid subscription item is considered cancelled" do
        copilot_product_uuid = create :billing_product_uuid, :copilot
        plan_subscription = create :billing_plan_subscription, :zuora
        user = plan_subscription.user
        subscription_item = create :billing_subscription_item, subscribable: copilot_product_uuid, plan_subscription: plan_subscription
        pending_plan_change = create :billing_pending_plan_change, user: user
        create :billing_pending_subscription_item_change, :cancellation, subscribable: copilot_product_uuid, pending_plan_change: pending_plan_change

        assert_equal 1, user.pending_subscription_item_changes.count

        result = subscription_item.cancel!(force: true).result

        assert result.success
        assert_predicate subscription_item.reload, :cancelled?
        assert_equal 0, user.pending_subscription_item_changes.count
      end

      # https://github.com/github/sponsors/issues/5222
      test "cancels pending subscription item changes when a sponsorship subscription item is cancelled" do
        plan_subscription = create(:billing_plan_subscription, purpose: :sponsors)
        user = plan_subscription.user
        sponsorship = create(:sponsorship, sponsor: user)
        sponsors_tier = sponsorship.tier
        subscription_item = sponsorship.subscription_item
        pending_plan_change = create(:billing_pending_plan_change, user: user)
        create(:billing_pending_subscription_item_change, :cancellation,
          subscribable: sponsors_tier,
          pending_plan_change: pending_plan_change,
        )

        assert_equal 1, user.pending_subscription_item_changes.count

        result = subscription_item.cancel!(force: true).result

        assert result.success
        assert_predicate subscription_item.reload, :cancelled?
        assert_equal 0, user.pending_subscription_item_changes.count
      end

      test "does not cancel pending subscription item changes when the product uuid subscription item is not considered as cancelled" do
        copilot_product_uuid = create :billing_product_uuid, :copilot
        plan_subscription = create :billing_plan_subscription, :zuora
        user = plan_subscription.user
        subscription_item = create :billing_subscription_item, subscribable: copilot_product_uuid, plan_subscription: plan_subscription
        pending_plan_change = create :billing_pending_plan_change, user: user
        create :billing_pending_subscription_item_change, subscribable: copilot_product_uuid, pending_plan_change: pending_plan_change

        assert_equal 1, user.pending_subscription_item_changes.count

        result = subscription_item.cancel!(force: false).result

        assert result.success
        refute_predicate subscription_item.reload, :cancelled?
        assert_equal 1, user.pending_subscription_item_changes.count
      end

      context "self-serve payment enterprise account orgs" do
        test "cancels marketplace item for specific org" do
          business = create :business, :with_self_serve_payment
          org1 = create :organization, business: business
          org2 = create :organization, business: business

          plan_subscription = create :billing_plan_subscription, :business_owned, customer: business.customer
          listing_plan = create(:marketplace_listing_plan, :verified_listing)
          subscription_item_org1 = create :billing_subscription_item,
            plan_subscription: plan_subscription,
            subscribable: listing_plan,
            quantity: 1,
            organization: org1

          subscription_item_org2 = create :billing_subscription_item,
            plan_subscription: plan_subscription,
            subscribable: listing_plan,
            quantity: 1,
            organization: org2

          result = subscription_item_org1.cancel!(force: true, actor: business.owners.first).result
          assert result.success
          assert_predicate subscription_item_org1.reload, :cancelled?
          refute_predicate subscription_item_org2.reload, :cancelled?
        end
      end
    end

    context "#cancel_and_refund!" do
      test "enqueues a job to cancel and refund the subscription item" do
        subscription_item = create :billing_subscription_item, :with_copilot_product_uuid
        assert_enqueued_with(job: Billing::CancelAndRefundSubscriptionItemJob, args: [subscription_item, organization_id: nil, full_refund: false, allow_cancelling_iap: false]) do
          subscription_item.cancel_and_refund!
        end
      end

      test "enqueues a job with the organization ID if given" do
        subscription_item = create :billing_subscription_item, :with_copilot_product_uuid
        organization = create :organization

        assert_enqueued_with(job: Billing::CancelAndRefundSubscriptionItemJob, args: [subscription_item, organization_id: organization.id, full_refund: false, allow_cancelling_iap: false]) do
          subscription_item.cancel_and_refund!(organization: organization)
        end
      end

      test "enqueues a job with allow_cancelling_iap if given" do
        subscription_item = create :billing_subscription_item, :with_copilot_product_uuid

        assert_enqueued_with(job: Billing::CancelAndRefundSubscriptionItemJob, args: [subscription_item, organization_id: nil, full_refund: false, allow_cancelling_iap: true]) do
          subscription_item.cancel_and_refund!(allow_cancelling_iap: true)
        end
      end
    end

    context "#extend_trial!" do
      test "Returns an error if pending change is not present" do
        marketplace_item = create(:billing_subscription_item, :free_trial)
        assert marketplace_item.on_free_trial?
        result = marketplace_item.extend_trial!(actor: marketplace_item.account, days: 2)
        refute result.ok?
        assert_equal "No pending change found.", result.error.message
      end

      test "Returns an error if days is <= 0" do
        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        item_id = @business.advanced_security_subscription_item.id
        subscription_item = Billing::SubscriptionItem.find(item_id)
        assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

        result = subscription_item.extend_trial!(actor: @owner, days: 0)
        refute result.ok?
        assert_equal "Days should be > 0 if extending a trial.", result.error.message
      end

      test "Returns an error if we attempt to extend trial past 60 days from today" do
        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        item_id = @business.advanced_security_subscription_item.id
        subscription_item = Billing::SubscriptionItem.find(item_id)
        assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

        result = subscription_item.extend_trial!(actor: @owner, days: 40)
        refute result.ok?
        assert_equal "Trial extension should be <= 60 days from today.", result.error.message
      end

      test "Returns an error if subscription item is not adminable by actor" do
        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        rando = create(:user)

        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        item_id = @business.advanced_security_subscription_item.id
        subscription_item = Billing::SubscriptionItem.find(item_id)
        assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

        result = subscription_item.extend_trial!(actor: rando, days: 2)
        refute result.ok?
        assert_equal "#{rando} does not have permission to manage this account (#{@business})", result.error.message
      end

      test "Can extend a trial" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 30.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date + 1.day, @business.pending_plan_changes.first.active_on

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          result = subscription_item.extend_trial!(actor: @owner, days: 3)
          assert result.ok?
          assert result.value!.on_free_trial?

          subscription_item.reload

          assert @business.has_active_advanced_security_trial?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date + 3.days + 1.day, @business.pending_plan_changes.first.active_on
          assert_equal free_trial_end_date + 3.days, subscription_item.free_trial_ends_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
        end
      end

      test "When extending a trial, rolls back free_trial_ends_on update when an error is raised" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 30.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date + 1.day, @business.pending_plan_changes.first.active_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          Billing::PendingPlanChange.any_instance.stubs(:update!).raises(ActiveRecord::RecordNotSaved.new("Failed to save the record"))

          Failbot.expects(:report).with(
            instance_of(ActiveRecord::RecordNotSaved),
            {
              :catalog_service => "github/ghas_self_serve_trial",
              "gh.account.id" => @business.id,
              "gh.account.type" => "Business",
              "gh.billing.subscription_item.id" => subscription_item.id
            }
          )

          result = subscription_item.extend_trial!(actor: @owner, days: 3)
          refute result.ok?
          assert_equal "Failed to extend trial. Reason: ActiveRecord::RecordNotSaved Failed to save the record", result.error.message

          subscription_item.reload

          assert @business.has_active_advanced_security_trial?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date + 1.day, @business.pending_plan_changes.first.active_on
          assert_equal free_trial_end_date, subscription_item.free_trial_ends_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
        end
      end

      test "When extending a trial, rolls back active_on update when an error is raised" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 30.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date + 1.day, @business.pending_plan_changes.first.active_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          Billing::SubscriptionItem.any_instance.stubs(:update!).raises(ActiveRecord::RecordNotSaved.new("Failed to save the record"))
          Failbot.expects(:report).with(
            instance_of(ActiveRecord::RecordNotSaved),
            {
              :catalog_service => "github/ghas_self_serve_trial",
              "gh.account.id" => @business.id,
              "gh.account.type" => "Business",
              "gh.billing.subscription_item.id" => subscription_item.id
            }
          )

          result = subscription_item.extend_trial!(actor: @owner, days: 3)
          refute result.ok?
          assert_equal "Failed to extend trial. Reason: ActiveRecord::RecordNotSaved Failed to save the record", result.error.message

          subscription_item.reload

          assert @business.has_active_advanced_security_trial?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date + 1.day, @business.pending_plan_changes.first.active_on
          assert_equal free_trial_end_date, subscription_item.free_trial_ends_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
        end
      end
    end

    context "#end_free_trial_now!" do
      test "Returns an error if not on free trial" do
        marketplace_item = create(:billing_subscription_item)
        refute marketplace_item.on_free_trial?
        result = marketplace_item.end_free_trial_now!(purchase_subscription: true, seats: 5, actor: marketplace_item.account)
        refute result.ok?
        assert_equal "Cannot end trial when trial is not active.", result.error.message
      end

      context "when pending subscription item change is missing" do
        test "Returns an error if something goes wrong" do
          GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          # destroy the underlying subscription item change, but have the pending plan change run
          change = subscription_item.pending_subscription_item_change.pending_plan_change
          subscription_item.pending_subscription_item_change.destroy
          subscription_item.reload
          change.run

          Billing::SubscriptionItemUpdater.expects(:perform).raises(::Platform::Errors::Unprocessable.new("boom"))

          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: false, actor: @owner)
              refute result.ok?
              subscription_item.reload
              assert subscription_item.on_free_trial?
              assert_equal "boom", result.error.message
            end
          end

          @business.reload
          assert_equal 1, subscription_item.reload.quantity
          assert @business.has_active_advanced_security_trial?
        end

        test "Returns an error if ActiveRecord raises" do
          GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          # destroy the underlying subscription item change, but have the pending plan change run
          change = subscription_item.pending_subscription_item_change.pending_plan_change
          subscription_item.pending_subscription_item_change.destroy
          subscription_item.reload
          change.run

          Billing::SubscriptionItem.any_instance.stubs(:update).returns(false)

          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: false, actor: @owner)
              refute result.ok?
              subscription_item.reload
              assert subscription_item.on_free_trial?
              assert_equal "Subscription item did not update with errors: Failed to end trial with missing pending change. Please try again.", result.error.message
            end
          end

          @business.reload
          assert_equal 1, subscription_item.reload.quantity
          assert @business.has_active_advanced_security_trial?
        end

        test "Ends free trial and cancels" do
          GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          # destroy the underlying subscription item change, but have the pending plan change run
          change = subscription_item.pending_subscription_item_change.pending_plan_change
          subscription_item.pending_subscription_item_change.destroy
          subscription_item.reload
          change.run

          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: false, actor: @owner)
              assert result.ok?
              refute result.value!.on_free_trial?
            end
          end

          @business.reload
          assert_equal 0, subscription_item.reload.quantity
          refute @business.has_active_advanced_security_trial?
          refute subscription_item.reload.on_free_trial?
        end

        test "Ends free trial and purchases" do
          jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

          GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

          travel_to jan_1st do
            free_trial_end_date = GitHub::Billing.today + 31.days
            result = @business.subscribe_to_advanced_security_trial(
              actor: @owner,
              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
            assert result.ok?
            assert result.value!.on_free_trial?
            assert @business.advanced_security_purchased_for_entity?
            assert_equal 1, @business.pending_plan_changes.count
            assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on


            item_id = @business.advanced_security_subscription_item.id
            subscription_item = Billing::SubscriptionItem.find(item_id)
            assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

            # destroy the underlying subscription item change, but have the pending plan change run
            change = subscription_item.pending_subscription_item_change.pending_plan_change
            subscription_item.pending_subscription_item_change.destroy
            subscription_item.reload
            change.run

            assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
              assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
                result = subscription_item.end_free_trial_now!(purchase_subscription: true, seats: 5, actor: @owner)
                assert result.ok?
                refute result.value!.on_free_trial?
              end
            end

            assert @business.advanced_security_purchased_for_entity?
            refute @business.has_active_advanced_security_trial?
            assert @business.has_advanced_security_trial_in_the_last_year?
            assert_equal 5, @business.advanced_security_seats_for_entity
            assert_equal 1, @business.pending_plan_changes.count
            assert @business.pending_plan_changes.first.is_complete
            assert_equal GitHub::Billing.today, @business.pending_plan_changes.first.active_on
            assert_equal 5, subscription_item.reload.quantity
          end
        end

        test "ends trial and purchases but does not enqueue synchronization job when skip_sync is true" do
          jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

          GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

          travel_to jan_1st do
            free_trial_end_date = GitHub::Billing.today + 31.days
            result = @business.subscribe_to_advanced_security_trial(
              actor: @owner,
              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
            assert result.ok?
            assert result.value!.on_free_trial?
            assert @business.advanced_security_purchased_for_entity?
            assert_equal 1, @business.pending_plan_changes.count
            assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on


            item_id = @business.advanced_security_subscription_item.id
            subscription_item = Billing::SubscriptionItem.find(item_id)
            assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

            # destroy the underlying subscription item change, but have the pending plan change run
            change = subscription_item.pending_subscription_item_change.pending_plan_change
            subscription_item.pending_subscription_item_change.destroy
            subscription_item.reload
            change.run

            assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
              assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
                result = subscription_item.end_free_trial_now!(purchase_subscription: true, seats: 5, actor: @owner, skip_sync: true)
                assert result.ok?
                refute result.value!.on_free_trial?
              end
            end

            assert @business.advanced_security_purchased_for_entity?
            refute @business.has_active_advanced_security_trial?
            assert @business.has_advanced_security_trial_in_the_last_year?
            assert_equal 5, @business.advanced_security_seats_for_entity
            assert_equal 1, @business.pending_plan_changes.count
            assert @business.pending_plan_changes.first.is_complete
            assert_equal GitHub::Billing.today, @business.pending_plan_changes.first.active_on
            assert_equal 5, subscription_item.reload.quantity
          end
        end
      end

      test "Returns an error if subscription item is not adminable by actor" do
        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        rando = create(:user)

        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        item_id = @business.advanced_security_subscription_item.id
        subscription_item = Billing::SubscriptionItem.find(item_id)
        assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

        result = subscription_item.end_free_trial_now!(purchase_subscription: false, actor: rando)
        refute result.ok?
        assert_equal "#{rando} does not have permission to manage this account (#{@business})", result.error.message
      end

      test "When purchasing, rolls back quantity update when an error is raised" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 31.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          Billing::PendingSubscriptionItemChange.any_instance.stubs(:update!).raises(ActiveRecord::RecordNotSaved.new("Failed to save the record"))
          Failbot.expects(:report).with(
            instance_of(ActiveRecord::RecordNotSaved),
            {
              :catalog_service => "github/ghas_self_serve_trial",
              "gh.account.id" => @business.id,
              "gh.account.type" => "Business",
              "gh.billing.subscription_item.id" => subscription_item.id
            }
          )

          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: true, seats: 5, actor: @owner)
              refute result.ok?
              assert_equal "Failed to end trial. Reason: ActiveRecord::RecordNotSaved Failed to save the record", result.error.message
            end
          end

          assert @business.advanced_security_purchased_for_entity?
          assert @business.has_active_advanced_security_trial?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
          refute @business.pending_plan_changes.first.is_complete
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
        end
      end

      test "When cancelling, rolls back quantity update when an error is raised" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 31.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          Billing::PendingSubscriptionItemChange.any_instance.stubs(:update!).raises(ActiveRecord::RecordNotSaved.new("Failed to save the record"))
          Failbot.expects(:report).with(
            instance_of(ActiveRecord::RecordNotSaved),
            {
               :catalog_service => "github/ghas_self_serve_trial",
              "gh.account.id" => @business.id,
              "gh.account.type" => "Business",
              "gh.billing.subscription_item.id" => subscription_item.id
            }
          )
          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: false, actor: @owner)
              refute result.ok?
              assert_equal "Failed to end trial. Reason: ActiveRecord::RecordNotSaved Failed to save the record", result.error.message
            end
          end

          assert @business.advanced_security_purchased_for_entity?
          assert @business.has_active_advanced_security_trial?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
          refute @business.pending_plan_changes.first.is_complete
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
        end
      end

      test "When purchasing, rolls back quantity update and active_on update when error is raised" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 31.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          Billing::PendingPlanChange.any_instance.stubs(:update!).raises(ActiveRecord::RecordNotSaved.new("Failed to save the record"))
          Failbot.expects(:report).with(
            instance_of(ActiveRecord::RecordNotSaved),
            {
              :catalog_service => "github/ghas_self_serve_trial",
              "gh.account.id" => @business.id,
              "gh.account.type" => "Business",
              "gh.billing.subscription_item.id" => subscription_item.id
            }
          )
          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: true, seats: 5, actor: @owner)
              refute result.ok?
              assert_equal "Failed to end trial. Reason: ActiveRecord::RecordNotSaved Failed to save the record", result.error.message
            end
          end

          assert @business.advanced_security_purchased_for_entity?
          assert @business.has_active_advanced_security_trial?
          assert_equal 1, @business.pending_plan_changes.count
          refute @business.pending_plan_changes.first.is_complete
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
        end
      end

      test "When cancelling, rolls back quantity update and active_on update when error is raised" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 31.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          Billing::PendingPlanChange.any_instance.stubs(:update!).raises(ActiveRecord::RecordNotSaved.new("Failed to save the record"))
          Failbot.expects(:report).with(
            instance_of(ActiveRecord::RecordNotSaved),
            {
              :catalog_service => "github/ghas_self_serve_trial",
              "gh.account.id" => @business.id,
              "gh.account.type" => "Business",
              "gh.billing.subscription_item.id" => subscription_item.id
            }
          )
          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: false, actor: @owner)
              refute result.ok?
              assert_equal "Failed to end trial. Reason: ActiveRecord::RecordNotSaved Failed to save the record", result.error.message
            end
          end

          assert @business.advanced_security_purchased_for_entity?
          assert @business.has_active_advanced_security_trial?
          assert_equal 1, @business.pending_plan_changes.count
          refute @business.pending_plan_changes.first.is_complete
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
        end
      end

      test "When purchasing, rolls back quantity update and active_on update when pending change fails to run" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 31.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          Billing::PendingPlanChange.any_instance.stubs(:run).returns(false)
          Failbot.expects(:report).with(
            instance_of(Billing::Public::BillingError),
            {
              :catalog_service => "github/ghas_self_serve_trial",
              "gh.account.id" => @business.id,
              "gh.account.type" => "Business",
              "gh.billing.subscription_item.id" => subscription_item.id
            }
          )
          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: true, seats: 5, actor: @owner)
              refute result.ok?
              assert_equal "Failed to run pending plan change.", result.error.message
            end
          end

          assert @business.advanced_security_purchased_for_entity?
          assert @business.has_active_advanced_security_trial?
          assert_equal 1, @business.pending_plan_changes.count
          refute @business.pending_plan_changes.first.is_complete
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
        end
      end

      test "When cancelling, rolls back quantity update and active_on update when pending change fails to run" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 31.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          Billing::PendingPlanChange.any_instance.stubs(:run).returns(false)
          Failbot.expects(:report).with(
            instance_of(Billing::Public::BillingError),
            {
              :catalog_service => "github/ghas_self_serve_trial",
              "gh.account.id" => @business.id,
              "gh.account.type" => "Business",
              "gh.billing.subscription_item.id" => subscription_item.id
            }
          )

          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: false, actor: @owner)
              refute result.ok?
              assert_equal "Failed to run pending plan change.", result.error.message
            end
          end

          assert @business.advanced_security_purchased_for_entity?
          assert @business.has_active_advanced_security_trial?
          assert_equal 1, @business.pending_plan_changes.count
          refute @business.pending_plan_changes.first.is_complete
          assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
          assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on
        end
      end

      test "Ends free trial immediately and purchases" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 31.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: true, seats: 5, actor: @owner)
              assert result.ok?
              refute result.value!.on_free_trial?
              RunPendingPlanChangeJob.perform_now(@business.pending_plan_changes.first)
            end
          end

          assert @business.advanced_security_purchased_for_entity?
          refute @business.has_active_advanced_security_trial?
          assert @business.has_advanced_security_trial_in_the_last_year?
          assert_equal 5, @business.advanced_security_seats_for_entity
          assert_equal 1, @business.pending_plan_changes.count
          assert @business.pending_plan_changes.first.is_complete
          assert_equal GitHub::Billing.today, @business.pending_plan_changes.first.active_on
          assert_equal 5, subscription_item.reload.quantity
        end
      end

      test "Ends free trial immediately and cancels" do
        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        item_id = @business.advanced_security_subscription_item.id
        subscription_item = Billing::SubscriptionItem.find(item_id)
        assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
            result = subscription_item.end_free_trial_now!(purchase_subscription: false, actor: @owner)
            assert result.ok?
            refute result.value!.on_free_trial?
          end
        end

        assert_equal 0, subscription_item.reload.quantity
        assert_equal 0, @business.pending_plan_changes.count
      end

      test "ends trial and purchases and does not enqueue synchronization job when `skip_sync` is true" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 31.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count
          assert_equal free_trial_end_date, @business.pending_plan_changes.first.active_on

          item_id = @business.advanced_security_subscription_item.id
          subscription_item = Billing::SubscriptionItem.find(item_id)
          assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = subscription_item.end_free_trial_now!(purchase_subscription: true, seats: 5, actor: @owner, skip_sync: true)
              assert result.ok?
              refute result.value!.on_free_trial?
              RunPendingPlanChangeJob.perform_now(@business.pending_plan_changes.first)
            end
          end

          assert @business.advanced_security_purchased_for_entity?
          refute @business.has_active_advanced_security_trial?
          assert @business.has_advanced_security_trial_in_the_last_year?
          assert_equal 5, @business.advanced_security_seats_for_entity
          assert_equal 1, @business.pending_plan_changes.count
          assert @business.pending_plan_changes.first.is_complete
          assert_equal GitHub::Billing.today, @business.pending_plan_changes.first.active_on
          assert_equal 5, subscription_item.reload.quantity
        end
      end
    end

    context "#listing_id" do
      test "returns the ID of the associated Sponsors listing" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, listing: listing)
        sub_item = create(:sponsors_subscription_item, subscribable: tier)

        assert_equal listing.id, sub_item.listing_id
      end

      test "returns the ID of the associated Marketplace listing" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
        sub_item = create(:billing_subscription_item, subscribable: listing_plan)

        assert_equal listing.id, sub_item.listing_id
      end

      # https://github.com/github/sponsors/issues/5519
      test "returns nil when the subscribable no longer exists" do
        listing = create(:sponsors_listing, :approved, tier_count: 0)
        tier = create(:sponsors_tier, :published, listing: listing)
        sub_item = create(:sponsors_subscription_item, subscribable: tier)
        tier.delete

        assert_nil sub_item.reload.listing_id
      end
    end

    context "#latest_billing_transaction" do
      test "returns the latest billing transaction" do
        subscription_item = create(:billing_subscription_item)
        old_billing_transaction = create(:billing_transaction, user: subscription_item.user, amount_in_cents: 1000)
        create(:billing_transaction_line_item, billing_transaction: old_billing_transaction, subscribable: subscription_item.subscribable)

        latest_transaction = create(:billing_transaction, user: subscription_item.user, amount_in_cents: 1000)
        create(:billing_transaction_line_item, billing_transaction: latest_transaction, subscribable: subscription_item.subscribable)

        assert_equal latest_transaction, subscription_item.latest_billing_transaction
      end

      test "returns the latest billing transaction even when old service_end_date" do
        travel_to 3.months.ago do
          subscription_item = create(:billing_subscription_item)
          most_recent_but_old_transaction = create(:billing_transaction, user: subscription_item.user, amount_in_cents: 1000)
          create(
            :billing_transaction_line_item,
            billing_transaction: most_recent_but_old_transaction,
            subscribable: subscription_item.subscribable,
            service_end_date: Date.today.next_month
          )
          assert_equal most_recent_but_old_transaction, subscription_item.latest_billing_transaction
        end
      end
    end

    context "#account and #async_account" do
      test "returns billable entity for the subscription item's plan subscription" do
        user = create(:credit_card_user, :verified)
        plan_sub = create(:billing_plan_subscription, :zuora, user: user)
        sub_item = create(:billing_subscription_item, plan_subscription: plan_sub)

        assert_equal user, sub_item.account
        assert_equal user, sub_item.async_account.sync
      end

      # https://github.com/github/sponsors/issues/5473
      test "returns sponsor when subscribable is a SponsorsTier and the subscription item has no plan subscription" do
        sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
        sponsorship = create(:sponsorship, sponsor: sponsor)
        subscription_item = sponsorship.subscription_item
        assert_predicate subscription_item, :subscribable_SponsorsTier?, "need a SponsorsTier subscribable"
        subscription_item.plan_subscription.delete
        subscription_item.reload

        assert_equal sponsor, subscription_item.account
        assert_equal sponsor, subscription_item.async_account.sync
      end

      test "returns nil when subscribable is not a SponsorsTier and the subscription item has no plan subscription" do
        user = create(:credit_card_user, :verified)
        plan_sub = create(:billing_plan_subscription, :zuora, user: user)
        sub_item = create(:billing_subscription_item, plan_subscription: plan_sub)
        refute_predicate sub_item, :subscribable_SponsorsTier?, "need a non-SponsorsTier subscribable"
        plan_sub.delete
        sub_item.reload

        assert_nil sub_item.account
        assert_nil sub_item.async_account.sync
      end
    end

    context "#active_billing_transaction" do
      test "returns the latest billing transaction" do
        subscription_item = T.let(nil, T.nilable(Billing::SubscriptionItem))
        latest_transaction = T.let(nil, T.nilable(Billing::BillingTransaction))
        travel_to 1.month.ago do
          subscription_item = create(:billing_subscription_item)
          old_billing_transaction = create(:billing_transaction, user: subscription_item.user, amount_in_cents: 1000)
          create(:billing_transaction_line_item, billing_transaction: old_billing_transaction, subscribable: subscription_item.subscribable)
        end

        subscription_item = T.must(subscription_item)

        travel_to 1.week.ago do
          latest_transaction = create(:billing_transaction, user: subscription_item.user, amount_in_cents: 1000)
          create(
            :billing_transaction_line_item,
            billing_transaction: latest_transaction,
            subscribable: subscription_item.subscribable,
            service_end_date: Time.now.next_month
          )
        end

        latest_transaction = T.must(latest_transaction)

        assert_equal latest_transaction, subscription_item.active_billing_transaction(start_date: Date.today)
      end

      test "returns nil with old latest service_end_date" do
        subscription_item = T.let(nil, T.nilable(Billing::SubscriptionItem))
        travel_to 3.months.ago do
          subscription_item = create(:billing_subscription_item)
          most_recent_but_old_transaction = create(:billing_transaction, user: subscription_item.user, amount_in_cents: 1000)
          create(:billing_transaction_line_item, billing_transaction: most_recent_but_old_transaction, subscribable: subscription_item.subscribable, service_end_date: Time.now.next_month)
        end

        assert_nil T.must(subscription_item).active_billing_transaction(start_date: Date.today)
      end
    end

    context "#activating?" do
      test "true if being created with a non-zero quantity" do
        sub_item = build(:billing_subscription_item, quantity: 1)
        assert_predicate sub_item, :activating?
      end

      test "true if being updated from a zero to positive quantity" do
        sub_item = create(:billing_subscription_item, quantity: 0)
        sub_item.quantity = 1
        assert_predicate sub_item, :activating?
      end

      test "false if being created with a zero quantity" do
        sub_item = build(:billing_subscription_item, quantity: 0)
        refute_predicate sub_item, :activating?
      end

      test "false if being updated from a non-zero to zero quantity" do
        sub_item = create(:billing_subscription_item, quantity: 1)
        sub_item.quantity = 0
        refute_predicate sub_item, :activating?
      end

      test "false if not updating the quantity" do
        sub_item = create(:billing_subscription_item, quantity: 1)
        sub_item.free_trial_ends_on = GitHub::Billing.today
        refute_predicate sub_item, :activating?
      end
    end

    context "#pending_cancellation?" do
      context "when there is not a pending_subscription_item_change" do
        test "it is not pending cancellation" do
          subscription_item = create(:billing_subscription_item)

          refute subscription_item.pending_cancellation?
        end
      end

      context "when there is a pending_subscription_item_change that isn't a cancellation" do
        test "it is not pending cancellation" do
          subscription_item = create(:billing_subscription_item)
          account = subscription_item.account
          change = create(:billing_pending_plan_change, user: account)
          create(:billing_pending_subscription_item_change,
                 pending_plan_change: change,
                 subscribable: subscription_item.subscribable,
                 plan_subscription: account.plan_subscription)

          refute subscription_item.pending_cancellation?
        end
      end

      context "when there is a pending_subscription_item_change that is a cancellation" do
        test "it is pending cancellation" do
          subscription_item = create(:billing_subscription_item)
          account = subscription_item.account
          change = create(:billing_pending_plan_change, user: account)
          create(:billing_pending_subscription_item_change,
                 :cancellation,
                 pending_plan_change: change,
                 subscribable: subscription_item.subscribable,
                 plan_subscription: account.plan_subscription)

          assert subscription_item.pending_cancellation?
        end
      end
    end
  end

  class AttemptToDowngradePlanToFreeWhenRecordDestroyedOrUpdatedToZeroQuantityTest < GitHub::TestCase
    test "downgrades the plan to `free` if we're destroying the last subscription item, there's no datapacks, and the current plan is `free_with_addons`" do
      organization = create(:credit_card_organization, plan: GitHub::Plan::FREE_WITH_ADDONS)
      subscription_item = create(:billing_subscription_item, account: organization)

      subscription_item.destroy

      assert_equal GitHub::Plan::FREE, organization.reload.plan.name
    end

    test "downgrades the plan to `free` if we're updating the quantity to zero, there are no other paid subscription items or datapacks, and the current plan is `free_with_addons`" do
      organization = create(:credit_card_organization, plan: GitHub::Plan::FREE_WITH_ADDONS)
      subscription_item = create(:billing_subscription_item, account: organization)

      subscription_item.update(quantity: 0)

      assert_equal GitHub::Plan::FREE, organization.reload.plan.name
    end

    test "does not change the plan to `free` if the current plan isn't `free_with_addons` even if we're deleting the last subscription item and there are no datapacks" do
      organization = create(:credit_card_organization, plan: GitHub::Plan::BUSINESS_PLUS)
      subscription_item = create(:billing_subscription_item, account: organization)

      subscription_item.destroy

      assert_equal GitHub::Plan::BUSINESS_PLUS, organization.reload.plan.name
    end

    test "does not change the plan to `free` if the quantity is updated to a non-zero amount" do
      organization = create(:credit_card_organization, plan: GitHub::Plan::FREE_WITH_ADDONS)
      subscription_item = create(:billing_subscription_item, account: organization)

      subscription_item.update(quantity: 10)

      assert_equal GitHub::Plan::FREE_WITH_ADDONS, organization.reload.plan.name
    end

    test "does not raise an error when the associated user is destroyed" do
      subscription_item = create(:billing_subscription_item)
      user = User.find(subscription_item.account.id)

      assert_nothing_raised do
        user.destroy
      end
    end

    context "#async_viewable_by?" do
      test "returns true if subscribed user is viewer" do
        subscription_item = create(:billing_subscription_item)
        user = subscription_item.account

        assert subscription_item.async_viewable_by?(user).sync
      end

      test "returns true for site admin" do
        subscription_item = create(:billing_subscription_item)
        staffer = create(:staff_admin_user)

        assert subscription_item.async_viewable_by?(staffer).sync
      end

      test "returns true for billing manager of subscribed org" do
        org = create(:organization)
        billing_manager = create(:user)
        org.billing.add_manager(billing_manager, actor: org.admin)
        assert org.billing_manager?(billing_manager)
        subscription_item = create(:billing_subscription_item, account: org)

        assert subscription_item.async_viewable_by?(billing_manager).sync
      end

      test "returns true for owner of subscribed org" do
        org = create(:organization)
        subscription_item = create(:billing_subscription_item, account: org)

        assert subscription_item.async_viewable_by?(org.admin).sync
      end

      test "returns true if listing plan is adminable" do
        app = create :oauth_application
        listing = create(:marketplace_listing, listable: app)
        plan = create(:marketplace_listing_plan, :published, listing: listing)
        subscription_item = create(:billing_subscription_item, subscribable: plan)

        assert subscription_item.async_viewable_by?(app.user).sync
      end

      test "returns false for random user" do
        subscription_item = create(:billing_subscription_item)
        refute subscription_item.async_viewable_by?(create(:user)).sync
      end

      test "returns false for logged out user" do
        subscription_item = create(:billing_subscription_item)
        refute subscription_item.async_viewable_by?(nil).sync
      end

      context "self-serve payment enterprise account orgs" do
        test "returns true for owner of Enterprise Account with a subscribed EA org" do
          business = create(:business, :with_self_serve_payment)
          business_owner_org_admin = business.owners.first
          org = create :organization, business: business, admin: business_owner_org_admin
          subscription_item = create(:billing_subscription_item, account: org, organization: org)

          assert subscription_item.async_viewable_by?(business_owner_org_admin).sync
        end

        test "returns true for admin of subscribed EA org" do
          business = create(:business, :with_self_serve_payment)
          org = create :organization, business: business
          subscription_item = create(:billing_subscription_item, account: org, organization: org)

          assert subscription_item.async_viewable_by?(org.admin).sync
        end

        test "returns false for random user" do
          business = create(:business, :with_self_serve_payment)
          org = create :organization, business: business
          subscription_item = create(:billing_subscription_item, account: org, organization: org)

          refute subscription_item.async_viewable_by?(create(:user)).sync
        end

        test "returns false for org member" do
          business = create(:business, :with_self_serve_payment)
          org = create :organization, business: business
          subscription_item = create(:billing_subscription_item, account: org, organization: org)
          member = create(:user)
          org.add_member(member)

          refute subscription_item.async_viewable_by?(member).sync
        end
      end
    end

    context "#in_app_purchase" do
      test "reconstitutes the in-app purchase from the apple subscription data" do
        copilot_product_uuid = create(:billing_product_uuid, :copilot)
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        subscription_item = create(:billing_subscription_item, :iap, subscribable: copilot_product_uuid, plan_subscription:)

        expected_in_app_purchase = Billing::Public::InAppPurchase.apple(
          original_transaction_id: subscription_item.apple_subscription.original_transaction_id
        )

        assert_equal expected_in_app_purchase, subscription_item.in_app_purchase
      end

      test "reconstitutes the in-app purchase from the google subscription data" do
        copilot_product_uuid = create(:billing_product_uuid, :copilot)
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        subscription_item = create(:billing_subscription_item, :google_iap, subscribable: copilot_product_uuid, plan_subscription:)

        expected_in_app_purchase = Billing::Public::InAppPurchase.google(
          purchase_token: subscription_item.google_subscription.purchase_token
        )

        assert_equal expected_in_app_purchase, subscription_item.in_app_purchase
      end
    end
  end
end
