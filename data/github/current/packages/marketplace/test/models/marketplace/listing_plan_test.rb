# typed: true
# frozen_string_literal: true

require "test_helper"

module Marketplace
  class ListingPlanTest < GitHub::BillingTestCase
    setup do
      FakeZuora.mock
    end

    fixtures do
      @listing = create(:marketplace_listing)
    end

    context "#same_listing?" do
      test "returns false when given something other than a Marketplace listing plan" do
        listing_plan = create(:marketplace_listing_plan, listing: @listing)
        refute listing_plan.same_listing?(nil)
        refute listing_plan.same_listing?(create(:sponsors_tier))
      end

      test "returns true when given the same tier" do
        listing_plan = create(:marketplace_listing_plan, listing: @listing)
        assert listing_plan.same_listing?(listing_plan)
      end

      test "returns true when given a different tier from the same Marketplace listing" do
        listing_plan = create(:marketplace_listing_plan, listing: @listing)
        other_listing_plan = create(:marketplace_listing_plan, listing: @listing)
        assert listing_plan.same_listing?(other_listing_plan)
      end

      test "returns false when given a different tier from a different Marketplace listing" do
        listing_plan1 = create(:marketplace_listing_plan, listing: @listing)
        listing_plan2 = create(:marketplace_listing_plan)
        refute listing_plan1.same_listing?(listing_plan2)
      end
    end

    context "#can_be_concurrent_with_subscription_item_for?" do
      test "returns true when given no other subscribable" do
        listing_plan = create(:marketplace_listing_plan, :published, listing: @listing)
        assert listing_plan.can_be_concurrent_with_subscription_item_for?(nil)
      end

      test "returns true when given a subscribable that isn't a Marketplace listing plan" do
        listing_plan = create(:marketplace_listing_plan, :published, listing: @listing)
        other_subscribable = create(:sponsors_tier, :published)
        assert listing_plan.can_be_concurrent_with_subscription_item_for?(other_subscribable)
      end

      test "returns true when given a plan for another Marketplace listing" do
        listing_plan = create(:marketplace_listing_plan, :published, listing: @listing)
        other_listing_plan = create(:marketplace_listing_plan, :published)
        refute_equal other_listing_plan.listing, listing_plan.listing

        assert listing_plan.can_be_concurrent_with_subscription_item_for?(other_listing_plan)
      end

      test "returns false when a plan is given another plan for the same Marketplace listing" do
        listing_plan1 = create(:marketplace_listing_plan, :published, listing: @listing)
        listing_plan2 = create(:marketplace_listing_plan, :published, listing: @listing)

        refute listing_plan1.can_be_concurrent_with_subscription_item_for?(listing_plan2)
      end
    end

    context "#available_for_purchase?" do
      test "true when plan is published" do
        plan = build(:marketplace_listing_plan, :published)
        assert_predicate plan, :available_for_purchase?
      end

      test "false when plan is a draft" do
        plan = build(:marketplace_listing_plan, :draft)
        refute_predicate plan, :available_for_purchase?
      end

      test "false when plan is retired" do
        plan = build(:marketplace_listing_plan, :retired)
        refute_predicate plan, :available_for_purchase?
      end
    end

    context "#price_model" do
      test "returns correct value for direct-billing plans" do
        plan = create(:marketplace_listing_plan, :direct_billing)

        assert_equal Marketplace::ListingPlan::DIRECT_BILLING_PRICE_MODEL, plan.price_model
      end
    end

    context "#can_subscribe_with_account?" do
      test "org only plans cannot be subscribed to by a user" do
        user = create(:user)
        plan = create(:marketplace_listing_plan, :organizations_only)

        refute plan.can_subscribe_with_account?(user)
      end

      test "org only plans can be subscribed to by an org" do
        org = create(:organization)
        plan = create(:marketplace_listing_plan, :organizations_only)

        assert plan.can_subscribe_with_account?(org)
      end

      test "user only plans cannot be subscribed to by an org" do
        org = create(:organization)
        plan = create(:marketplace_listing_plan, :users_only)

        refute plan.can_subscribe_with_account?(org)
      end

      test "user only plans can be subscribed to by a user" do
        user = create(:user)
        plan = create(:marketplace_listing_plan, :users_only)

        assert plan.can_subscribe_with_account?(user)
      end
    end

    context "#for_users_only?" do
      test "default value is false" do
        plan = build(:marketplace_listing_plan)

        refute_predicate plan, :for_users_only?
      end
    end

    context "#for_organizations_only?" do
      test "default value is false" do
        plan = build(:marketplace_listing_plan)

        refute_predicate plan, :for_organizations_only?
      end
    end

    context "state" do
      test "default state is draft" do
        plan = create(:marketplace_listing_plan, listing: @listing)

        assert_equal :draft, plan.current_state.name
        assert_predicate plan, :draft?
      end

      test "can initialize to published" do
        plan = create(:marketplace_listing_plan, :published, listing: @listing)

        assert_equal :published, plan.current_state.name
        assert_predicate plan, :published?
      end

      test "can initialize to retired" do
        plan = create(:marketplace_listing_plan, :retired, listing: @listing)

        assert_equal :retired, plan.current_state.name
        assert_predicate plan, :retired?
      end

      test "can initialize to a non-default state with block" do
        plan = Marketplace::ListingPlan.new(listing: @listing) do |p|
          p.state = T.unsafe(:published)
        end

        assert_equal :published, plan.current_state.name
        assert_predicate plan, :published?
      end

      test "transitions from draft to published when under plan limit" do
        plan = create(:marketplace_listing_plan)

        plan.listing.listable = create(:oauth_application, user: create(:organization))
        plan.listing.owner.creator_verification_state_update(create(:biztools_user), Configurable::MarketplaceCreatorVerification::APPROVED)
        # new process listing needs min installations even in draft mode.
        Marketplace::Listing::REQUIRED_INSTALLS_FOR_OAUTH_APP.times do
          OauthAuthorization.create!(application: plan.listing.listable, user: create(:user))
        end

        plan.publish!

        assert_predicate plan, :published?
      end

      test "transitions from draft to published are instrumented" do
        events = subscribe "marketplace_listing_plan.publish"
        plan = create(:marketplace_listing_plan)

        plan.listing.listable = create(:oauth_application, user: create(:organization))
        plan.listing.owner.creator_verification_state_update(create(:biztools_user), Configurable::MarketplaceCreatorVerification::APPROVED)
        # new process listing needs min installations even in draft mode.
        Marketplace::Listing::REQUIRED_INSTALLS_FOR_OAUTH_APP.times do
          OauthAuthorization.create!(application: plan.listing.listable, user: create(:user))
        end

        plan.publish!

        assert_predicate plan, :published?
        assert event = events.pop, "an event was expected"
        assert_equal "marketplace_listing_plan.publish", event.name
      end

      test "does not transition from draft to published when at plan limit" do
        listing = create(:marketplace_listing)

        Marketplace::ListingPlan::PLAN_LIMIT_PER_LISTING.times do
          create(:marketplace_listing_plan, :published, listing: listing)
        end

        plan = create(:marketplace_listing_plan, listing: listing)

        assert_raises(Workflow::NoTransitionAllowed) { plan.publish! }

        refute_predicate plan, :published?
      end

      Marketplace::Listing::RESTRICTED_REGIONS.each do |region|
        test "does not transition from draft to published when owner is from #{region}" do
          listing = create(:marketplace_listing)

          plan = create(:marketplace_listing_plan, :paid, :draft, listing: listing)
          listing.owner.update(profile_location: region)
          assert_raises(Workflow::NoTransitionAllowed) { plan.publish! }

          refute_predicate plan, :published?
        end
      end

      Marketplace::Listing::RESTRICTED_REGIONS.each do |region|
        test "transitions free plan from draft to published for restricted #{region}" do
          listing = create(:marketplace_listing)

          plan = create(:marketplace_listing_plan, :free, :draft, listing: listing)
          listing.owner.update(profile_location: region)

          assert_enqueued_with(job: MarketplaceListingPlanZuoraSyncJob, args: [plan]) do
            plan.publish!
          end

          assert_predicate plan, :published?
        end
      end

      test "transitions free plan from draft to published when listing is unverified" do
        listing = create(:marketplace_listing, :unverified)
        plan = create(:marketplace_listing_plan, :free, :draft, listing: listing)

        plan.publish!

        assert_predicate plan, :published?
      end

      test "does not transition paid plan from draft to published when listing is unverified" do
        listing = create(:marketplace_listing, :unverified)
        plan = create(:marketplace_listing_plan, :paid, :draft, listing: listing)

        assert_raises(Workflow::NoTransitionAllowed) { plan.publish! }

        refute_predicate plan, :published?
      end

      test "transitions from published to retired" do
        listing = create(:marketplace_listing)
        plan = create(:marketplace_listing_plan, :published, listing: listing)

        create(:marketplace_listing_plan, :published, listing: listing)

        plan.retire!

        assert_predicate plan, :retired?
      end

      test "transition to retired is instrumented" do
        events = subscribe "marketplace_listing_plan.retire"

        listing = create(:marketplace_listing)
        plan = create(:marketplace_listing_plan, :published, listing: listing)

        create(:marketplace_listing_plan, :published, listing: listing)

        plan.retire!

        assert_predicate plan, :retired?
        assert event = events.pop, "an event was expected"
        assert_equal "marketplace_listing_plan.retire", event.name
      end

      test "updates filter categories on publish" do
        plan = create(:marketplace_listing_plan)

        plan.listing.expects(:set_filter_categories!)

        plan.listing.listable = create(:oauth_application, user: create(:organization))
        plan.listing.owner.creator_verification_state_update(create(:biztools_user), Configurable::MarketplaceCreatorVerification::APPROVED)
        # new process listing needs min installations even in draft mode.
        Marketplace::Listing::REQUIRED_INSTALLS_FOR_OAUTH_APP.times do
          OauthAuthorization.create!(application: plan.listing.listable, user: create(:user))
        end

        plan.publish!

        assert_predicate plan, :published?
      end

      test "updates filter categories on retire" do
        plan = create(:marketplace_listing_plan, :published)
        create(:marketplace_listing_plan, :published, listing: plan.listing)

        plan.listing.expects(:set_filter_categories!)

        plan.retire!

        assert_predicate plan, :retired?
      end

      test "syncs to zuora on publish" do
        listing = create(:marketplace_listing, :verified_publisher)
        plan = create(:marketplace_listing_plan, listing: listing)

        # new process listing needs min installations even in draft mode.
        Marketplace::Listing::REQUIRED_INSTALLS_FOR_OAUTH_APP.times do
          OauthAuthorization.create!(application: plan.listing.listable, user: create(:user))
        end

        assert_enqueued_with(job: MarketplaceListingPlanZuoraSyncJob, args: [plan]) do
          plan.publish!
        end

        assert_predicate plan, :published?
      end

      test "doesn't sync to zuora on retire" do
        listing = create(:marketplace_listing)
        plan = create(:marketplace_listing_plan, :published, listing: listing)

        create(:marketplace_listing_plan, :published, listing: listing)

        plan.expects(:sync_to_zuora).never

        plan.retire!

        assert_predicate plan, :retired?
      end
    end

    context "#monthly_price_in_dollars" do
      test "does not discard cents" do
        listing_plan = Marketplace::ListingPlan.new(monthly_price_in_cents: 867)
        assert_equal 8.67, listing_plan.monthly_price_in_dollars
      end
    end

    context "#yearly_price_in_dollars" do
      test "does not discard cents" do
        listing_plan = Marketplace::ListingPlan.new(yearly_price_in_cents: 10404)
        assert_equal 104.04, listing_plan.yearly_price_in_dollars
      end
    end

    context ".base_price" do
      test "returns the monthly_price_in_cents" do
        listing_plan = build(:marketplace_listing_plan, monthly_price_in_cents: 1_00)

        assert_money 1_00, listing_plan.base_price # defaults to month
        assert_money 1_00, listing_plan.base_price(duration: :month)
      end

      test "returns the yearly_price_in_cents" do
        listing_plan = build(:marketplace_listing_plan, yearly_price_in_cents: 2_00)

        assert_money 2_00, listing_plan.base_price(duration: :year)
      end
    end

    context "validations" do
      test "validates numericality of monthly_price_in_cents" do
        listing_plan = build(:marketplace_listing_plan, monthly_price_in_cents: "dog")

        refute listing_plan.valid?
        assert_includes listing_plan.errors[:monthly_price_in_cents], "is not a number"
      end

      test "validates numericality of yearly_price_in_cents" do
        listing_plan = build(:marketplace_listing_plan, yearly_price_in_cents: "dog")

        refute listing_plan.valid?
        assert_includes listing_plan.errors[:yearly_price_in_cents], "is not a number"
      end

      test "validates monthly_price_in_cents is greater than or equal to 0" do
        listing_plan = build(:marketplace_listing_plan, monthly_price_in_cents: -1)

        refute listing_plan.valid?
        assert_includes listing_plan.errors[:monthly_price_in_cents],
          "must be greater than or equal to 0"
      end

      test "validates monthly_price_in_cents is less than or equal to 999_999_999" do
        listing_plan = build(:marketplace_listing_plan, monthly_price_in_cents: 1_000_000_000)

        refute listing_plan.valid?
        assert_includes listing_plan.errors[:monthly_price_in_cents],
          "must be less than or equal to 999999999"
      end

      test "validates yearly_price_in_cents is greater than or equal to 0" do
        listing_plan = build(:marketplace_listing_plan, yearly_price_in_cents: -1)

        refute listing_plan.valid?
        assert_includes listing_plan.errors[:yearly_price_in_cents],
          "must be greater than or equal to 0"
      end

      test "validates yearly_price_in_cents is less than or equal to 999_999_999" do
        listing_plan = build(:marketplace_listing_plan, yearly_price_in_cents: 1_000_000_000)

        refute listing_plan.valid?
        assert_includes listing_plan.errors[:yearly_price_in_cents],
          "must be less than or equal to 999999999"
      end

      test "validates that it is either completely free or paid" do
        listing_plan = build(:marketplace_listing_plan, monthly_price_in_cents: 0,
                             yearly_price_in_cents: 12_00)

        refute listing_plan.valid?
        assert_includes listing_plan.errors[:yearly_price_in_cents],
          "must be zero since the monthly price is zero, or choose free pricing model"

        listing_plan = build(:marketplace_listing_plan, monthly_price_in_cents: 12_00,
                             yearly_price_in_cents: 0)

        refute listing_plan.valid?
        assert_includes listing_plan.errors[:monthly_price_in_cents],
          "must be zero since the yearly price is zero, or choose free pricing model"
      end

      test "validates that direct billing plans are allowed for the listing" do
        listing = create(:marketplace_listing, direct_billing_enabled: false)
        plan = build(:marketplace_listing_plan, :direct_billing, listing: listing)

        refute_predicate plan, :valid?
        assert_includes plan.errors[:price_model], "listing cannot have direct billing plans"
      end

      test "validates that direct billing plans cannot have free trials" do
        listing = create(:marketplace_listing, direct_billing_enabled: true)
        plan = build(:marketplace_listing_plan, :direct_billing, listing: listing, has_free_trial: true)

        refute_predicate plan, :valid?
        assert_includes plan.errors[:has_free_trial], "is only allowed for paid plans"
      end

      test "validates that direct billing plans must have zero price values" do
        listing = create(:marketplace_listing, direct_billing_enabled: true)
        plan = build(:marketplace_listing_plan, :direct_billing,
          listing: listing,
          monthly_price_in_cents: 10_00,
          yearly_price_in_cents: 100_00
        )

        refute_predicate plan, :valid?
        assert_includes plan.errors[:monthly_price_in_cents], "must be zero for price model"
        assert_includes plan.errors[:yearly_price_in_cents], "must be zero for price model"
      end

      test "validates that units aren't set for direct billing plans" do
        listing = create(:marketplace_listing, direct_billing_enabled: true)
        plan = build(:marketplace_listing_plan, :direct_billing,
          listing: listing,
          per_unit: true,
          unit_name: "seat"
        )

        refute_predicate plan, :valid?
        assert_includes plan.errors[:per_unit], "is not allowed for price model"
        assert_includes plan.errors[:unit_name], "cannot be set if price model is not 'per unit'"
      end

      test "validates that free plans cannot have free trials" do
        plan = build(:marketplace_listing_plan, :free, per_unit: true, has_free_trial: true)

        refute_predicate plan, :valid?
        assert_includes plan.errors[:has_free_trial], "is only allowed for paid plans"
      end

      test "validates that units aren't set for free plans" do
        plan = build(:marketplace_listing_plan, :free, per_unit: true, unit_name: "seat")

        refute_predicate plan, :valid?
        assert_includes plan.errors[:per_unit], "is not allowed for price model"
        assert_includes plan.errors[:unit_name], "cannot be set if price model is not 'per unit'"
      end

      test "validates that pricing cannot be changed for Published plans on Approved listings" do
        plan = create(:marketplace_listing_plan, :published, listing: create(:marketplace_listing, :verified))

        plan.monthly_price_in_cents = 100
        plan.yearly_price_in_cents = 1000
        plan.unit_name = "User"

        refute_predicate plan, :valid?
        assert plan.errors[:price_model]
        assert plan.errors[:monthly_price_in_cents]
        assert plan.errors[:yearly_price_in_cents]
      end

      test "validates length of name" do
        listing = create(:marketplace_listing)
        text = "a" * (Marketplace::ListingPlan::NAME_MAX_LENGTH + 1)
        plan = build(:marketplace_listing_plan, listing: listing, name: text)

        refute_predicate plan, :valid?
        assert_predicate plan.errors[:name], :any?
      end

      test "validates length of unit_name" do
        listing = create(:marketplace_listing)
        text = "a" * (Marketplace::ListingPlan::UNIT_NAME_MAX_LENGTH + 1)
        plan = build(:marketplace_listing_plan, listing: listing, unit_name: text)

        refute_predicate plan, :valid?
        assert_predicate plan.errors[:unit_name], :any?
      end

      test "validates name cannot be changed if state isn't editable" do
        listing = create(:marketplace_listing, :verified)
        plan = create(:marketplace_listing_plan, :published, listing: listing)

        assert_predicate plan, :valid?

        plan.name = "new name"

        refute_predicate plan, :valid?
        assert_predicate plan.errors[:name], :any?
      end

      test "limits number of published plans allowed per listing" do
        create(:marketplace_listing_plan, :retired, listing: @listing)
        Marketplace::ListingPlan::PLAN_LIMIT_PER_LISTING.times do
          create(:marketplace_listing_plan, :published, listing: @listing)
        end

        assert_equal Marketplace::ListingPlan::PLAN_LIMIT_PER_LISTING + 1,
          @listing.listing_plans.count

        plan = build(:marketplace_listing_plan, :published, listing: @listing)

        refute_predicate plan, :valid?
        assert_predicate plan.errors[:listing], :any?
      end

      test "ignores per-listing plan limit when creating a draft plan" do
        Marketplace::ListingPlan::PLAN_LIMIT_PER_LISTING.times do
          create(:marketplace_listing_plan, listing: @listing)
        end

        plan = build(:marketplace_listing_plan, listing: @listing)

        assert_predicate plan, :valid?
      end

      test "ignores per-listing plan limit when creating a retired plan" do
        Marketplace::ListingPlan::PLAN_LIMIT_PER_LISTING.times do
          create(:marketplace_listing_plan, listing: @listing)
        end

        plan = build(:marketplace_listing_plan, :retired, listing: @listing)

        assert_predicate plan, :valid?
      end

      test "requires a listing" do
        plan = Marketplace::ListingPlan.new(listing: nil)

        refute_predicate plan, :valid?
        assert_predicate plan.errors[:listing], :any?
      end

      [:name, :description, :monthly_price_in_cents, :yearly_price_in_cents].each do |attr|
        test "requires #{attr}" do
          plan = Marketplace::ListingPlan.new
          plan.send(:write_attribute, attr, nil)

          refute_predicate plan, :valid?
          assert_predicate plan.errors[attr], :any?
        end
      end

      test "requires a unique name per published listing plan" do
        existing_plan = create(:marketplace_listing_plan, :published, listing: @listing)
        plan = build(:marketplace_listing_plan, :published, listing: @listing, name: existing_plan.name)

        refute_predicate plan, :valid?
        assert_predicate plan.errors[:name], :any?
      end

      test "does not include retired plans when validating name uniqueness" do
        retired_plan = create(:marketplace_listing_plan, :retired, listing: @listing)

        dup_retired_plan = build(:marketplace_listing_plan,
          :retired, listing: @listing, name: retired_plan.name
        )
        dup_published_plan = build(:marketplace_listing_plan,
          :published, listing: @listing, name: retired_plan.name
        )

        assert_predicate dup_retired_plan, :valid?
        assert_predicate dup_published_plan, :valid?
      end

      test "does not require unique pricing per published marketplace listing plan" do
        existing_plan = create(:marketplace_listing_plan, :published, listing: @listing)
        plan = build(:marketplace_listing_plan, :published, listing: @listing, monthly_price_in_cents: existing_plan.monthly_price_in_cents)

        assert_predicate plan, :valid?
        refute_predicate plan.errors[:monthly_price_in_cents], :any?
      end

      test "requires a unit name if per unit" do
        plan = Marketplace::ListingPlan.new(per_unit: true, unit_name: "")

        refute_predicate plan, :valid?
        assert_predicate plan.errors[:unit_name], :any?
      end
    end

    context "sequence number" do
      test "validation creates a sequence for the listing" do
        listing = create(:marketplace_listing)
        plan = build(:marketplace_listing_plan, listing: listing)

        refute Sequence.exists?(listing)

        plan.valid?

        assert Sequence.exists?(listing)
        assert_equal 1, plan.number
      end

      test "validation uses existing sequence for the listing" do
        listing = create(:marketplace_listing)
        plan = build(:marketplace_listing_plan, listing: listing)

        Sequence.create(listing, 41)
        plan.valid?

        assert_equal 42, plan.number
      end

      test "validation sets sequence number if listing is present" do
        listing = create(:marketplace_listing)
        plan = build(:marketplace_listing_plan, listing: listing)

        assert_equal 0, plan.number
        assert_predicate plan, :valid?
        assert plan.number > 0, "sequence number was not updated"
      end

      test "validation does not set sequence number if listing is not present" do
        plan = build(:marketplace_listing_plan, listing: nil)

        assert_equal 0, plan.number
        refute_predicate plan, :valid?
        assert_equal 0, plan.number
      end

      test "continues sequence after plans are retired" do
        listing = create(:marketplace_listing)
        plan1 = create(:marketplace_listing_plan, :published, listing: listing)
        plan2 = create(:marketplace_listing_plan, :published, listing: listing)

        assert_no_difference "plan2.number" do
          plan2.retire!
        end

        plan3 = build(:marketplace_listing_plan, listing: listing)
        assert_predicate plan3, :valid?
        assert_equal plan2.number + 1, plan3.number
      end

      test "continues sequence after plans are destroyed" do
        listing = create(:marketplace_listing)
        plan1 = create(:marketplace_listing_plan, :published, listing: listing)
        plan2 = create(:marketplace_listing_plan, :published, listing: listing)

        assert_no_difference "Sequence.get(listing)" do
          plan2.destroy
        end

        plan3 = build(:marketplace_listing_plan, listing: listing)
        assert_predicate plan3, :valid?
        assert_equal plan2.number + 1, plan3.number
      end
    end

    context "#paid?" do
      test "true when monthly_price_in_cents is more than zero" do
        plan = create(:marketplace_listing_plan, monthly_price_in_cents: 100)

        assert_predicate plan, :paid?
      end

      test "true when yearly_price_in_cents is more than zero" do
        plan = create(:marketplace_listing_plan, yearly_price_in_cents: 1200)

        assert_predicate plan, :paid?
      end

      test "false when monthly_price_in_cents and yearly_price_in_cents are both zero" do
        plan = create(:marketplace_listing_plan, monthly_price_in_cents: 0, yearly_price_in_cents: 0)

        refute_predicate plan, :paid?
      end
    end

    context "#visible_to?" do
      test "true when listing is approved" do
        listing = create(:marketplace_listing, :verified)
        plan = create(:marketplace_listing_plan, listing: listing)

        assert plan.visible_to?(create(:user))
        assert plan.visible_to?(nil), "should be visible to anonymous user"
      end

      test "false when listing is delisted" do
        listing = create(:marketplace_listing, :archived)
        plan = create(:marketplace_listing_plan, listing: listing)

        refute plan.visible_to?(create(:user))
      end

      test "false when listing is draft" do
        listing = create(:marketplace_listing, :draft)
        plan = create(:marketplace_listing_plan, listing: listing)

        refute plan.visible_to?(create(:user))
      end

      test "false when listing is verification_pending_from_draft" do
        listing = create(:marketplace_listing, :verification_pending_from_draft)
        plan = create(:marketplace_listing_plan, listing: listing)

        refute plan.visible_to?(create(:user))
      end
    end

    context "with_free_trial scope" do
      test "includes plans with a free trial" do
        plan1 = create(:marketplace_listing_plan, :verified_listing, has_free_trial: true)
        plan2 = create(:marketplace_listing_plan, :verified_listing, has_free_trial: false)

        results = Marketplace::ListingPlan.with_free_trial

        assert_includes results, plan1
        refute_includes results, plan2
      end

      test "filters by state if one is provided" do
        # has free trial and correct state:
        plan1 = create(:marketplace_listing_plan, :verified_listing, state: :retired,
                                              has_free_trial: true)

        # has free trial but not the right state:
        plan2 = create(:marketplace_listing_plan, :verified_listing, state: :published,
                                              has_free_trial: true)

        # has correct state but does not have free trial:
        plan3 = create(:marketplace_listing_plan, :verified_listing, state: :retired,
                                              has_free_trial: false)

        results = Marketplace::ListingPlan.with_free_trial(state: :retired)

        assert_includes results, plan1
        refute_includes results, plan2
        refute_includes results, plan3
      end
    end

    context "paid scope" do
      test "includes plan with an annual cost" do
        plan = create(:marketplace_listing_plan, yearly_price_in_cents: 500_00)
        assert_includes Marketplace::ListingPlan.paid, plan
      end

      test "includes plan with a monthly cost" do
        plan = create(:marketplace_listing_plan, monthly_price_in_cents: 10_00)
        assert_includes Marketplace::ListingPlan.paid, plan
      end

      test "excludes plan with no monthly or annual cost" do
        plan = create(:marketplace_listing_plan, monthly_price_in_cents: 0, yearly_price_in_cents: 0)
        refute_includes Marketplace::ListingPlan.paid, plan
      end
    end

    context "free scope" do
      test "excludes plan with an annual cost" do
        plan = create(:marketplace_listing_plan, yearly_price_in_cents: 500_00)
        refute_includes Marketplace::ListingPlan.free, plan
      end

      test "excludes plan with a monthly cost" do
        plan = create(:marketplace_listing_plan, monthly_price_in_cents: 10_00)
        refute_includes Marketplace::ListingPlan.free, plan
      end

      test "includes plan with no monthly or annual cost" do
        plan = create(:marketplace_listing_plan, monthly_price_in_cents: 0, yearly_price_in_cents: 0)
        assert_includes Marketplace::ListingPlan.free, plan
      end
    end

    context "#allowed_to_edit?" do
      test "true when user is integration owner admin" do
        integration = create(:integration)
        listing = create(:marketplace_listing, listable: integration)
        plan = create(:marketplace_listing_plan, listing: listing)

        assert plan.allowed_to_edit?(integration.owner.admin)
      end

      test "true when user is OAuth app user" do
        app = create :oauth_application
        listing = create(:marketplace_listing, listable: app)
        plan = create(:marketplace_listing_plan, listing: listing)

        assert plan.allowed_to_edit?(app.user)
      end

      test "false when user is unrelated to integration owner" do
        integration = create(:integration)
        listing = create(:marketplace_listing, listable: integration)
        plan = create(:marketplace_listing_plan, listing: listing)

        refute plan.allowed_to_edit?(create(:user))
      end

      test "false when user is a regular member of integration owner" do
        integration = create(:integration)
        member = create(:user)
        integration.owner.add_member(member)

        listing = create(:marketplace_listing, listable: integration)
        plan = create(:marketplace_listing_plan, listing: listing)

        refute plan.allowed_to_edit?(member)
      end

      test "false when user is not OAuth app user" do
        app = create :oauth_application
        listing = create(:marketplace_listing, listable: app)
        plan = create(:marketplace_listing_plan, listing: listing)

        refute plan.allowed_to_edit?(create(:user))
      end

      test "true when the plan is published" do
        app = create :oauth_application
        listing = create(:marketplace_listing, listable: app)
        plan = create(:marketplace_listing_plan, :published, listing: listing)

        assert plan.allowed_to_edit?(app.user)
      end

      test "false when the plan is retired" do
        app = create :oauth_application
        listing = create(:marketplace_listing, listable: app)
        plan = create(:marketplace_listing_plan, :retired, listing: listing)

        refute plan.allowed_to_edit?(app.user)
      end
    end

    context "#allowed_to_delete?" do
      test "true when user is integration owner admin" do
        integration = create(:integration)
        listing = create(:marketplace_listing, listable: integration)
        plan = create(:marketplace_listing_plan, listing: listing)

        assert plan.allowed_to_delete?(integration.owner.admin)
      end

      test "true when user is OAuth app user" do
        app = create :oauth_application
        listing = create(:marketplace_listing, listable: app)
        plan = create(:marketplace_listing_plan, listing: listing)

        assert plan.allowed_to_delete?(app.user)
      end

      test "false when user is unrelated to integration owner" do
        integration = create(:integration)
        listing = create(:marketplace_listing, listable: integration)
        plan = create(:marketplace_listing_plan, listing: listing)

        refute plan.allowed_to_delete?(create(:user))
      end

      test "false when user is a regular member of integration owner" do
        integration = create(:integration)
        member = create(:user)
        integration.owner.add_member(member)

        listing = create(:marketplace_listing, listable: integration)
        plan = create(:marketplace_listing_plan, listing: listing)

        refute plan.allowed_to_delete?(member)
      end

      test "false when user is not OAuth app user" do
        app = create :oauth_application
        listing = create(:marketplace_listing, listable: app)
        plan = create(:marketplace_listing_plan, listing: listing)

        refute plan.allowed_to_delete?(create(:user))
      end

      test "false when the plan is published and listing is approved" do
        app = create :oauth_application
        listing = create(:marketplace_listing, :verified, listable: app)
        plan = create(:marketplace_listing_plan, :published, listing: listing)

        refute plan.allowed_to_delete?(app.user)
      end

      test "true when the plan is published and listing is a draft" do
        app = create :oauth_application
        listing = create(:marketplace_listing, :draft, listable: app)
        plan = create(:marketplace_listing_plan, :published, listing: listing)

        assert plan.allowed_to_delete?(app.user)
      end

      test "false when the plan is retired" do
        listing = create(:marketplace_listing, :verified)
        plan = create(:marketplace_listing_plan, :retired, listing: listing)

        refute plan.allowed_to_delete?(listing.owner)
      end
    end

    context "#can_change_name?/#can_change_pricing?" do
      test "false when the plan is retired" do
        plan = build(:marketplace_listing_plan, :retired)

        refute plan.can_change_name?
        refute plan.can_change_pricing?
      end

      test "false when the Listing is approved and Plan is published" do
        listing = create(:marketplace_listing, :verified)
        plan = build(:marketplace_listing_plan, :published, listing: listing)

        refute plan.can_change_name?
        refute plan.can_change_pricing?
      end

      test "true when the Listing is approved and Plan is draft" do
        listing = create(:marketplace_listing, :verified)
        plan = build(:marketplace_listing_plan, :draft, listing: listing)

        assert plan.can_change_name?
        assert plan.can_change_pricing?
      end

      test "false when the Listing is draft and Plan is published" do
        listing = create(:marketplace_listing, :draft)
        plan = build(:marketplace_listing_plan, :published, listing: listing)

        refute plan.can_change_name?
        refute plan.can_change_pricing?
      end

      test "false when the Listing is draft and Plan is retired" do
        listing = create(:marketplace_listing, :draft)
        plan = build(:marketplace_listing_plan, :retired, listing: listing)

        refute plan.can_change_name?
        refute plan.can_change_pricing?
      end
    end

    context "#adminable_by?" do
      test "true when the listing is adminable by user" do
        app = create :oauth_application
        listing = create(:marketplace_listing, listable: app)
        plan = create(:marketplace_listing_plan, listing: listing)

        assert plan.adminable_by?(app.user)
      end

      test "false when the user doesn't have admin rights to listing" do
        user = create(:user)
        plan = build(:marketplace_listing_plan)

        refute plan.adminable_by?(user)
      end
    end

    context "#listing_type" do
      test "returns 'application' for plan for an OAuth app listing" do
        app = create :oauth_application
        listing = create(:marketplace_listing, listable: app)
        plan = create(:marketplace_listing_plan, listing: listing)

        assert_equal "application", plan.listing_type
      end

      test "returns 'integration' for plan for an integration listing" do
        integration = create(:integration)
        listing = create(:marketplace_listing, listable: integration)
        plan = create(:marketplace_listing_plan, listing: listing)

        assert_equal "integration", plan.listing_type
      end
    end

    context "#draft_listing?" do
      test "true when listing is a draft" do
        listing = create(:marketplace_listing, :draft)
        plan = create(:marketplace_listing_plan, listing: listing)

        assert_predicate plan, :draft_listing?
      end

      test "false when listing is not in draft state" do
        listing = create(:marketplace_listing, :verified)
        plan = create(:marketplace_listing_plan, listing: listing)

        refute_predicate plan, :draft_listing?
      end
    end

    context "plan deletions" do
      test "allow deletion when there are no associated subscription items" do
        listing = create(:marketplace_listing, :unverified)
        plan = create(:marketplace_listing_plan, :published, listing: listing)
        assert plan.destroy
      end

      test "allow deletion for draft listing when there are no associated subscription items" do
        listing = create(:marketplace_listing, :draft)
        plan = create(:marketplace_listing_plan, :published, listing: listing)
        assert plan.destroy
      end

      test "allow deletion for draft listing when there are associated subscription items" do
        listing = create(:marketplace_listing, :draft)
        plan = create(:marketplace_listing_plan, :published, listing: listing)
        create :billing_subscription_item,
          subscribable: plan
        assert plan.destroy
      end

      test "doesn't allow deletion for non draft listing when there are associated subscription items" do
        listing = create(:marketplace_listing, :unverified)
        plan = create(:marketplace_listing_plan, :published, listing: listing)
        create :billing_subscription_item,
          subscribable: plan
        refute plan.destroy
      end
    end

    test "removes associated plan changes on deletion" do
      plan = create(:billing_pending_subscription_item_change).subscribable

      assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
        plan.destroy
      end
    end

    context "#line_item_description" do
      test "includes listing name and plan name" do
        listing_plan = create(:marketplace_listing_plan, name: "My Fancy Marketplace Plan")
        assert_equal "#{listing_plan.listing.name} - My Fancy Marketplace Plan",
          listing_plan.line_item_description
      end
    end

    context "associations" do
      test "has many billing transaction line items" do
        listing_plan = create(:marketplace_listing_plan)

        assert listing_plan.billing_transaction_line_items.count
      end
    end

    context "#pending_subscription_item_change and #async_pending_subscription_item_change" do
      test "returns nil when there is no pending subscription item change" do
        listing_plan = create(:marketplace_listing_plan, :verified_listing)
        user = create(:user)

        assert_nil listing_plan.async_pending_subscription_item_change(account: user).sync
        assert_nil listing_plan.pending_subscription_item_change(account: user),
          "expected same result from non-async method"
      end

      test "returns pending downgrade" do
        listing = create(:marketplace_listing, :verified)
        listing_plan_expensive = create(:marketplace_listing_plan, listing: listing, state: :published)
        listing_plan_cheap = create(:marketplace_listing_plan, :paid, listing: listing, state: :published)

        subscription_item = create(:billing_subscription_item, subscribable: listing_plan_expensive)
        user = subscription_item.plan_subscription.user
        plan_change = create(:billing_pending_plan_change, user: user)
        pending_downgrade = create(:billing_pending_subscription_item_change, subscribable: listing_plan_cheap,
          pending_plan_change: plan_change)

        assert_equal pending_downgrade, listing_plan_expensive.reload
          .async_pending_subscription_item_change(account: user).sync
        assert_equal pending_downgrade, listing_plan_expensive.pending_subscription_item_change(account: user),
          "expected same result from non-async method"
      end

      test "returns pending cancellation" do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create(:marketplace_listing_plan, listing: listing, state: :published)
        subscription_item = create(:billing_subscription_item, subscribable: listing_plan)
        plan_sub = subscription_item.plan_subscription
        user = plan_sub.user
        plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 1.month, user: user)
        pending_cancellation = create(:billing_pending_subscription_item_change, :cancellation,
          subscribable: listing_plan, pending_plan_change: plan_change)

        assert_equal pending_cancellation, listing_plan.reload
          .async_pending_subscription_item_change(account: user).sync
        assert_equal pending_cancellation, listing_plan.pending_subscription_item_change(account: user),
          "expected same result from non-async method"
      end

      context "self-serve payment enterprise account orgs for marketplace" do
        test "returns nil when there is no pending subscription item change" do
          business = create :business, :with_self_serve_payment
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: business.customer
          business_admin = business.owners.first
          org = create :organization, business: business, admin: business_admin

          listing_plan = create(:marketplace_listing_plan, :verified_listing)

          assert_nil listing_plan.async_pending_subscription_item_change(account: business, organization: org).sync
          assert_nil listing_plan.pending_subscription_item_change(account: business, organization: org),
            "expected same result from non-async method"
        end

        test "returns pending downgrade" do
          listing = create(:marketplace_listing, :verified)
          listing_plan_expensive = create(:marketplace_listing_plan, listing: listing, state: :published)
          listing_plan_cheap = create(:marketplace_listing_plan, :paid, listing: listing, state: :published)

          business = create :business, :with_self_serve_payment
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: business.customer
          business_admin = business.owners.first
          org = create :organization, business: business, admin: business_admin

          subscription_item = create(:billing_subscription_item, subscribable: listing_plan_expensive,
            plan_subscription: plan_subscription, organization: org)
          plan_change = create(:billing_pending_plan_change, active_on: business.next_billing_date,
            user: nil, customer_id: business.customer.id)
          pending_downgrade = create(:billing_pending_subscription_item_change, subscribable: listing_plan_cheap,
            pending_plan_change: plan_change, organization: org)

          assert_equal pending_downgrade, listing_plan_expensive.reload
            .async_pending_subscription_item_change(account: business, organization: org).sync
          assert_equal pending_downgrade, listing_plan_expensive.pending_subscription_item_change(account: business, organization: org),
            "expected same result from non-async method"
        end

        test "returns pending cancellation" do
          listing = create(:marketplace_listing, :verified)
          listing_plan = create(:marketplace_listing_plan, listing: listing, state: :published)
          business = create :business, :with_self_serve_payment
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: business.customer
          business_admin = business.owners.first
          org = create :organization, business: business, admin: business_admin

          subscription_item = create(:billing_subscription_item, subscribable: listing_plan,
            plan_subscription: plan_subscription, organization: org)

          plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 1.month,
            user: nil, customer_id: business.customer.id)
          pending_cancellation = create(:billing_pending_subscription_item_change, :cancellation,
            subscribable: listing_plan, pending_plan_change: plan_change, organization: org)

          assert_equal pending_cancellation, listing_plan.reload
            .async_pending_subscription_item_change(account: business, organization: org).sync
          assert_equal pending_cancellation, listing_plan.pending_subscription_item_change(account: business, organization: org),
            "expected same result from non-async method"
        end
      end
    end

    context "free trials" do
      test "plans can be created with free trials" do
        listing_plan = create(:marketplace_listing_plan, has_free_trial: true)

        assert listing_plan.has_free_trial?
      end

      test "prorated_total_price accounts for free trials" do
        user = create(:user)
        listing_plan = create(:marketplace_listing_plan, :free_trial, monthly_price_in_cents: 10_00)

        assert_money 0_00, listing_plan.prorated_total_price(account: user, quantity: 1)
      end
    end

    context "#prorated_total_price" do
      test "calculates prorated total for yearly plans" do
        Timecop.freeze("2018-02-16") do
          user = create :user,
            plan_duration: User::BillingDependency::YEARLY_PLAN,
            billed_on: GitHub::Billing.today + 60.days
          listing_plan = create :marketplace_listing_plan,
            monthly_price_in_cents: 12_00,
            yearly_price_in_cents: 120_00

          # $12/month * (60/31) days = $23.22
          # Even though the user is on a yearly plan, prorated prices are
          # calculated on a monthly basis
          assert_money 23_22, listing_plan.prorated_total_price(account: user, quantity: 1)
        end
      end

      test "calculates a full period of service on the billing date" do
        Timecop.freeze do
          user = create(:user, plan_duration: User::BillingDependency::MONTHLY_PLAN, billed_on: GitHub::Billing.today)
          listing_plan = create(:marketplace_listing_plan, monthly_price_in_cents: 12_00)

          assert_money 12_00, listing_plan.prorated_total_price(account: user, quantity: 1)
        end
      end
    end
  end
end
