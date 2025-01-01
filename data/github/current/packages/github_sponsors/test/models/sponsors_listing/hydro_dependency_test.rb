# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroDependencyForSponsorsListingTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @sponsors_listing = create(:sponsors_listing, :approved)
    @sponsorable = @sponsors_listing.sponsorable
    @tier = create(:sponsors_tier, :published,
      sponsors_listing: @sponsors_listing,
      monthly_price_in_cents: 100_00,
    )

    @sponsor = create(:credit_card_user, :verified,
      plan_subscription: create(:billing_plan_subscription))
  end

  setup do
    @checkout_viewed_expected_payload = {
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      actor: Hydro::EntitySerializer.user(@sponsor),
      sponsorable: Hydro::EntitySerializer.user(@sponsorable),
      listing: Hydro::EntitySerializer.sponsors_listing(@sponsors_listing),
      sponsor: Hydro::EntitySerializer.user(@sponsor),
      tier: Hydro::EntitySerializer.sponsors_tier(@tier),
      checkout_type: SponsorsListing::HydroDependency::HYDRO_SPONSORSHIP_CHECKOUT_NEW,
      sponsor_plan_duration: SponsorsListing::HydroDependency::HYDRO_SPONSOR_PLAN_MONTHLY,
      is_sponsor_payment_method_valid: true,
      is_first_time_sponsor: true,
      is_data_collection_needed: false,
    }
  end

  context "#instrument_tier_builder_interaction" do
    test "sends a Hydro event when a user visits the Tier Builder page" do
      expected_payload = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@sponsorable),
        interaction: :VIEW,
        submitted_actions: []
      }

      SponsorsListing.instrument_view_tier_builder(actor: @sponsorable)

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.TierBuilderInteraction")
      assert_hydro_published(expected_payload,
                             schema: "github.sponsors.v1.TierBuilderInteraction",
                             ignore_extra_keys: true,
                             )
    end

    test "sends a Hydro event when a user skips the Tier Builder page" do
      expected_payload = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@sponsorable),
        interaction: :SKIP,
        submitted_actions: []
      }

      SponsorsListing.instrument_skip_tier_builder(actor: @sponsorable)

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.TierBuilderInteraction")
      assert_hydro_published(expected_payload,
                             schema: "github.sponsors.v1.TierBuilderInteraction",
                             ignore_extra_keys: true,
                             )
    end

    test "sends a Hydro event when a user implements suggestions, along with their mouseclicks, from the Tier Builder page" do
      submitted_actions = [
        { frequency: :MONTHLY, price_in_cents: 10_00, checked: true, description: "We will go to a cat cafe together" },
        { frequency: :MONTHLY, price_in_cents: 10_00, checked: false, description: "We will go to a cat cafe together" },
        { frequency: :ONE_TIME, price_in_cents: 200_00, checked: false, description: "Adopt a cat" }, # imagine this is a prechecked default
        { frequency: :ONE_TIME, price_in_cents: 500_00, checked: true, description: "Adopt every cat" },
      ]

      expected_payload = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@sponsorable),
        interaction: :SUBMIT,
        submitted_actions: submitted_actions,
      }

      SponsorsListing.instrument_submit_tier_builder_suggestions(actor: @sponsorable, submitted_actions: submitted_actions)

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.TierBuilderInteraction")
      assert_hydro_published(expected_payload,
                             schema: "github.sponsors.v1.TierBuilderInteraction",
                             ignore_extra_keys: true,
                             )
    end
  end

  context "#instrument_sponsorship_checkout_viewed" do
    test "sends event for brand new sponsorship checkouts" do
      @sponsors_listing.instrument_sponsorship_checkout_viewed(
        actor: @sponsor,
        sponsor: @sponsor,
        tier: @tier,
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.CheckoutViewed")
      assert_hydro_published(
        @checkout_viewed_expected_payload,
        schema: "github.sponsors.v0.CheckoutViewed",
      )
    end

    test "sends event for sponsorship reactivation" do
      create(:sponsorship, :inactive,
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        tier: @tier,
      )

      @sponsors_listing.instrument_sponsorship_checkout_viewed(
        actor: @sponsor,
        sponsor: @sponsor,
        tier: @tier,
      )

      expected_payload = @checkout_viewed_expected_payload.merge(
        is_first_time_sponsor: false,
        checkout_type: SponsorsListing::HydroDependency::HYDRO_SPONSORSHIP_CHECKOUT_REACTIVATION,
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.CheckoutViewed")
      assert_hydro_published(
        expected_payload,
        schema: "github.sponsors.v0.CheckoutViewed",
      )
    end

    test "sends event for sponsorship management" do
      create(:sponsorship,
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        tier: @tier,
      )

      @sponsors_listing.instrument_sponsorship_checkout_viewed(
        actor: @sponsor,
        sponsor: @sponsor,
        tier: @tier,
      )

      expected_payload = @checkout_viewed_expected_payload.merge(
        is_first_time_sponsor: false,
        checkout_type: SponsorsListing::HydroDependency::HYDRO_SPONSORSHIP_CHECKOUT_MANAGE,
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.CheckoutViewed")
      assert_hydro_published(
        expected_payload,
        schema: "github.sponsors.v0.CheckoutViewed",
      )
    end

    test "sends event for sponsorship downgrade" do
      create(:sponsorship,
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        tier: @tier,
      )

      new_tier = create(:sponsors_tier, :published,
        sponsors_listing: @sponsors_listing,
        monthly_price_in_cents: @tier.monthly_price_in_cents - 100,
      )

      @sponsors_listing.instrument_sponsorship_checkout_viewed(
        actor: @sponsor,
        sponsor: @sponsor,
        tier: new_tier,
      )

      expected_payload = @checkout_viewed_expected_payload.merge(
        is_first_time_sponsor: false,
        listing: Hydro::EntitySerializer.sponsors_listing(@sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(new_tier),
        checkout_type: SponsorsListing::HydroDependency::HYDRO_SPONSORSHIP_CHECKOUT_DOWNGRADE,
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.CheckoutViewed")
      assert_hydro_published(
        expected_payload,
        schema: "github.sponsors.v0.CheckoutViewed",
      )
    end

    test "sends event for sponsorship upgrade" do
      create(:sponsorship,
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        tier: @tier,
      )

      new_tier = create(:sponsors_tier, :published,
        sponsors_listing: @sponsors_listing,
        monthly_price_in_cents: @tier.monthly_price_in_cents + 100,
      )

      @sponsors_listing.instrument_sponsorship_checkout_viewed(
        actor: @sponsor,
        sponsor: @sponsor,
        tier: new_tier,
      )

      expected_payload = @checkout_viewed_expected_payload.merge(
        is_first_time_sponsor: false,
        listing: Hydro::EntitySerializer.sponsors_listing(@sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(new_tier),
        checkout_type: SponsorsListing::HydroDependency::HYDRO_SPONSORSHIP_CHECKOUT_UPGRADE,
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.CheckoutViewed")
      assert_hydro_published(
        expected_payload,
        schema: "github.sponsors.v0.CheckoutViewed",
      )
    end

    test "sends event for sponsor with yearly plan" do
      sponsor = create(:user, plan_duration: "year")

      @sponsors_listing.instrument_sponsorship_checkout_viewed(
        actor: sponsor,
        sponsor: sponsor,
        tier: @tier,
      )

      expected_payload = @checkout_viewed_expected_payload.merge(
        actor: Hydro::EntitySerializer.user(sponsor),
        sponsor: Hydro::EntitySerializer.user(sponsor),
        sponsor_plan_duration: SponsorsListing::HydroDependency::HYDRO_SPONSOR_PLAN_YEARLY,
        is_sponsor_payment_method_valid: false,
        is_data_collection_needed: true,
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.CheckoutViewed")
      assert_hydro_published(
        expected_payload,
        schema: "github.sponsors.v0.CheckoutViewed",
      )
    end

    test "sends event for sponsor with data collection needed" do
      sponsor = create(:user)

      @sponsors_listing.instrument_sponsorship_checkout_viewed(
        actor: sponsor,
        sponsor: sponsor,
        tier: @tier,
      )

      expected_payload = @checkout_viewed_expected_payload.merge(
        actor: Hydro::EntitySerializer.user(sponsor),
        sponsor: Hydro::EntitySerializer.user(sponsor),
        is_sponsor_payment_method_valid: false,
        is_data_collection_needed: true,
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.CheckoutViewed")
      assert_hydro_published(
        expected_payload,
        schema: "github.sponsors.v0.CheckoutViewed",
      )
    end
  end
end
