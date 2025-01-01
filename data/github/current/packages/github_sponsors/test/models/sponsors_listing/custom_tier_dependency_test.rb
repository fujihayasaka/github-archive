# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListing::CustomTierDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @approved_listing = create(:sponsors_listing, :approved)
  end

  context "validations" do
    test "validates suggested custom tier amount in cents is a whole dollar amount" do
      listing = SponsorsListing.new(suggested_custom_tier_amount_in_cents: 150) # $1.50
      refute_predicate listing, :valid?
      assert_includes listing.errors[:suggested_custom_tier_amount_in_cents],
        "must be divisible by 100"
    end

    test "validates suggested custom tier amount in cents is within dollar limit" do
      excessive_cents = SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_CENTS + 100
      listing = SponsorsListing.new(suggested_custom_tier_amount_in_cents: excessive_cents)
      refute_predicate listing, :valid?
      assert_includes listing.errors[:suggested_custom_tier_amount_in_cents],
        "exceeds maximum tier amount of #{SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN}"
    end

    test "validates minimum custom tier amount in cents is a whole dollar amount" do
      listing = SponsorsListing.new(min_custom_tier_amount_in_cents: 150) # $1.50
      refute_predicate listing, :valid?
      assert_includes listing.errors[:min_custom_tier_amount_in_cents], "must be divisible by 100"
    end

    test "doesn't mark listing invalid when there isn't a published tier" do
      listing = create(:sponsors_listing, :approved, tier_count: 1)
      listing.sponsors_tiers.with_published_state.destroy_all

      listing.match_disabled = !listing.match_disabled

      assert_predicate listing, :valid?, "should still be valid"
    end

    test "validates minimum custom tier amount in cents is within dollar limit" do
      excessive_cents = SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_CENTS + 100
      listing = SponsorsListing.new(min_custom_tier_amount_in_cents: excessive_cents)
      refute_predicate listing, :valid?
      assert_includes listing.errors[:min_custom_tier_amount_in_cents],
        "exceeds maximum tier amount of #{SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN}"
    end

    test "validates suggested custom tier amount in cents greater than minimum amount" do
      minimum = 5_00
      suggested = minimum - 1_00
      listing = SponsorsListing.new(
        min_custom_tier_amount_in_cents: minimum,
        suggested_custom_tier_amount_in_cents: suggested
      )
      refute_predicate listing, :valid?
      assert_includes listing.errors[:suggested_custom_tier_amount_in_cents],
        "must be at least the minimum amount for custom sponsorships"
      assert_includes listing.errors[:min_custom_tier_amount_in_cents],
        "must be no more than the suggested amount for custom sponsorships"
    end
  end

  context "#unique_custom_tiers" do
    test "returns a custom tier at each price point that has an active sponsorship" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)
      tier1 = create(:sponsors_tier, :custom, sponsors_listing: listing, monthly_price_in_cents: 5_00)
      create(:sponsorship, tier: tier1)
      tier2 = create(:sponsors_tier, :custom, sponsors_listing: listing, monthly_price_in_cents: 1_00)
      create(:sponsorship, tier: tier2)

      # Dupe amount to an earlier custom tier:
      tier3 = create(:sponsors_tier, :custom, sponsors_listing: listing, monthly_price_in_cents: 1_00)
      create(:sponsorship, tier: tier3)

      # Tier not used in any sponsorship:
      tier4 = create(:sponsors_tier, :custom, sponsors_listing: listing, monthly_price_in_cents: 3_00)

      # Tier used only in an inactive sponsorship:
      tier5 = create(:sponsors_tier, :custom, sponsors_listing: listing, monthly_price_in_cents: 8_00)
      create(:sponsorship, :inactive, tier: tier5)

      result = listing.unique_custom_tiers

      assert_includes result, tier1
      assert_includes result, tier2
      refute_includes result, tier3,
        "should not include a second custom tier with the same price as a custom tier with a lower ID"
      refute_includes result, tier4, "should not include tier not used in any sponsorship"
      refute_includes result, tier5, "should not include custom tier only used in an inactive sponsorship"
      assert_equal 2, result.size
    end
  end

  context "#instrument_custom_amount_settings_change" do
    test "instruments Hydro and audit log events for new value" do
      current_suggested_amount = @approved_listing.suggested_custom_tier_amount_in_cents.to_i / 100
      actor = @approved_listing.sponsorable
      events = subscribe("sponsors.custom_amount_settings_change")

      @approved_listing.instrument_custom_amount_settings_change(current_suggested_amount + 1, actor: actor)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(actor),
        listing: Hydro::EntitySerializer.sponsors_listing(@approved_listing),
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.CustomAmountSettingsChange")
      refute_empty events, "should have made a sponsors.custom_amount_settings_change event"
    end
  end

  context "#suggested_custom_tier_amount_in_dollars" do
    test "returns dollar amount of suggested custom tier amount" do
      listing = SponsorsListing.new(suggested_custom_tier_amount_in_cents: 5_00)
      assert_equal 5, listing.suggested_custom_tier_amount_in_dollars
    end

    test "returns nil when no cents are set on the listing" do
      listing = SponsorsListing.new(suggested_custom_tier_amount_in_cents: nil)
      assert_nil listing.suggested_custom_tier_amount_in_dollars
    end
  end

  context "#min_custom_tier_amount_in_dollars" do
    test "returns dollar amount of minimum custom tier amount" do
      listing = SponsorsListing.new(min_custom_tier_amount_in_cents: 5_00)
      assert_equal 5, listing.min_custom_tier_amount_in_dollars
    end

    test "returns nil when no cents is set on the listing" do
      listing = SponsorsListing.new(min_custom_tier_amount_in_cents: nil)
      assert_nil listing.min_custom_tier_amount_in_dollars
    end
  end
end
