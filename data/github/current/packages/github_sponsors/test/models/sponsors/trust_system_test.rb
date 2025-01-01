# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::TrustSystemTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @untrusted_sponsor = create(:user, plan_subscription: create(:billing_plan_subscription))
    @untrusted_sponsorable = create(:sponsorable_user, :untrusted,
      sponsors_tier_count: 0
    )
    @untrusted_sponsors_listing = @untrusted_sponsorable.sponsors_listing
    @neutrally_trusted_sponsorable = create(:sponsorable_user, :neutral_trust)
    @trusted_sponsorable = create(:sponsorable_user, :trusted)
  end

  context "hydro" do
    test "includes expected data" do
      Sponsors::TrustSystem.enough_trust_for_payout_info?(
        actor: @untrusted_sponsorable,
        sponsorable: @untrusted_sponsorable
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.FraudSystemActionProhibited")
      message = hydro_messages(schema: "github.sponsors.v1.FraudSystemActionProhibited").first

      assert_equal @untrusted_sponsorable.login, message[:actor][:login]
      assert_equal :VIEW_PAYOUT_INFO, message[:action]
      assert_equal :SPONSORABLE, message[:trust_target]
      assert_equal :UNTRUSTED, message[:trust_level]
      assert_nil message[:sponsor]
      assert_equal @untrusted_sponsorable.login, message[:sponsorable][:login]
      assert_equal @untrusted_sponsorable.id, message[:listing][:sponsorable_id]
      assert_equal @untrusted_sponsors_listing.id, message[:listing_stafftools_metadata][:sponsors_listing_id]
      assert_nil message[:tier]
    end

    test "emits message with enforced false when feature flag disabled" do
      GitHub.flipper[:sponsors_enforce_trust_system].disable

      Sponsors::TrustSystem.enough_trust_for_payout_info?(
        actor: @untrusted_sponsorable,
        sponsorable: @untrusted_sponsorable
      )

      message = hydro_messages(schema: "github.sponsors.v1.FraudSystemActionProhibited").first

      assert_equal false, message[:enforced]
    end

    test "emits message with enforced true when feature flag enabled" do
      GitHub.flipper[:sponsors_enforce_trust_system].enable

      Sponsors::TrustSystem.enough_trust_for_payout_info?(
        actor: @untrusted_sponsorable,
        sponsorable: @untrusted_sponsorable
      )

      message = hydro_messages(schema: "github.sponsors.v1.FraudSystemActionProhibited").first

      assert_equal true, message[:enforced]
    end
  end

  context "#enough_trust_for_payout_info?" do
    test "false when sponsorable is untrusted and feature flag enabled" do
      GitHub.flipper[:sponsors_enforce_trust_system].enable

      can_view_payout_info = Sponsors::TrustSystem.enough_trust_for_payout_info?(
        actor: @untrusted_sponsorable,
        sponsorable: @untrusted_sponsorable
      )
      assert_equal false, can_view_payout_info
    end

    test "true when sponsorable is untrusted and feature flag disabled" do
      GitHub.flipper[:sponsors_enforce_trust_system].disable

      can_view_payout_info = Sponsors::TrustSystem.enough_trust_for_payout_info?(
        actor: @untrusted_sponsorable,
        sponsorable: @untrusted_sponsorable
      )
      assert_equal true, can_view_payout_info
    end

    test "true when sponsorable has a neutral trust level" do
      can_view_payout_info = Sponsors::TrustSystem.enough_trust_for_payout_info?(
        actor: @neutrally_trusted_sponsorable,
        sponsorable: @neutrally_trusted_sponsorable
      )
      assert_equal true, can_view_payout_info
    end

    test "true when sponsorable is trusted" do
      can_view_payout_info = Sponsors::TrustSystem.enough_trust_for_payout_info?(
        actor: @trusted_sponsorable,
        sponsorable: @trusted_sponsorable
      )
      assert_equal true, can_view_payout_info
    end
  end

  context "#enough_trust_for_sponsorship?" do
    test "true when only one of sponsor and sponsorable is untrusted" do
      tier_above_limit = create(:sponsors_tier, :exceeds_untrusted_sponsorship_limit,
        sponsors_listing: @untrusted_sponsors_listing,
      )
      create(:sponsors_activity,
        sponsor: @neutrally_trusted_sponsorable,
        sponsorable: @untrusted_sponsorable,
        sponsors_tier: tier_above_limit,
      )

      # FIXME: assert_no_queries do
      assert Sponsors::TrustSystem.enough_trust_for_sponsorship?(
        actor: @neutrally_trusted_sponsorable,
        sponsor: @neutrally_trusted_sponsorable,
        sponsorable: @untrusted_sponsorable,
        tier: tier_above_limit,
      )
      # FIXME: end
    end

    test "true when both sponsor and sponsorable are untrusted and below total limit" do
      one_dollar_tier = create(:sponsors_tier,
        sponsors_listing: @untrusted_sponsors_listing,
        monthly_price_in_cents: 1_00,
      )

      assert Sponsors::TrustSystem.enough_trust_for_sponsorship?(
        actor: @untrusted_sponsor,
        sponsor: @untrusted_sponsor,
        sponsorable: @untrusted_sponsorable,
        tier: one_dollar_tier,
      )
    end

    test "true when both sponsor and sponsorable are untrusted and total above limit and feature flag disabled" do
      GitHub.flipper[:sponsors_enforce_trust_system].disable

      tier_above_limit = create(:sponsors_tier, :exceeds_untrusted_sponsorship_limit,
        sponsors_listing: @untrusted_sponsors_listing,
      )
      create(:sponsors_activity,
        sponsor: @untrusted_sponsor,
        sponsorable: @untrusted_sponsorable,
        sponsors_tier: tier_above_limit,
      )

      assert Sponsors::TrustSystem.enough_trust_for_sponsorship?(
        actor: @untrusted_sponsor,
        sponsor: @untrusted_sponsor,
        sponsorable: @untrusted_sponsorable,
        tier: tier_above_limit,
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.FraudSystemActionProhibited")
      message = hydro_messages(schema: "github.sponsors.v1.FraudSystemActionProhibited").first

      assert_equal @untrusted_sponsor.login, message[:actor][:login]
      assert_equal :CREATE_SPONSORSHIP, message[:action]
      assert_equal :SPONSORABLE, message[:trust_target]
      assert_equal :UNTRUSTED, message[:trust_level]
      assert_equal @untrusted_sponsor.login, message[:sponsor][:login]
      assert_equal @untrusted_sponsorable.login, message[:sponsorable][:login]
      assert_equal @untrusted_sponsorable.id, message[:listing][:sponsorable_id]
      assert_equal @untrusted_sponsors_listing.id, message[:listing_stafftools_metadata][:sponsors_listing_id]
      assert_equal tier_above_limit.id, message[:tier][:id]
    end

    test "false when both sponsor and sponsorable are untrusted and sponsor total above limit and feature flag enabled" do
      GitHub.flipper[:sponsors_enforce_trust_system].enable

      tier_above_limit = create(:sponsors_tier, :exceeds_untrusted_sponsorship_limit,
        sponsors_listing: @untrusted_sponsors_listing,
      )
      create(:sponsors_activity,
        sponsor: @untrusted_sponsor,
        sponsorable: @untrusted_sponsorable,
        sponsors_tier: tier_above_limit,
      )

      refute Sponsors::TrustSystem.enough_trust_for_sponsorship?(
        actor: @untrusted_sponsor,
        sponsor: @untrusted_sponsor,
        sponsorable: @untrusted_sponsorable,
        tier: tier_above_limit,
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.FraudSystemActionProhibited")
      message = hydro_messages(schema: "github.sponsors.v1.FraudSystemActionProhibited").first

      assert_equal @untrusted_sponsor.login, message[:actor][:login]
      assert_equal :CREATE_SPONSORSHIP, message[:action]
      assert_equal :SPONSORABLE, message[:trust_target]
      assert_equal :UNTRUSTED, message[:trust_level]
      assert_equal @untrusted_sponsor.login, message[:sponsor][:login]
      assert_equal @untrusted_sponsorable.login, message[:sponsorable][:login]
      assert_equal @untrusted_sponsorable.id, message[:listing][:sponsorable_id]
      assert_equal @untrusted_sponsors_listing.id, message[:listing_stafftools_metadata][:sponsors_listing_id]
      assert_equal tier_above_limit.id, message[:tier][:id]
    end

    test "false when both sponsor and sponsorable are untrusted and sponsorable total above limit and feature flag enabled" do
      GitHub.flipper[:sponsors_enforce_trust_system].enable

      other_untrusted_sponsor = create(:user)
      tier_above_limit = create(:sponsors_tier, :exceeds_untrusted_sponsorship_limit,
        sponsors_listing: @untrusted_sponsors_listing,
      )
      one_dollar_tier = create(:sponsors_tier,
        sponsors_listing: @untrusted_sponsors_listing,
        monthly_price_in_cents: 1_00,
      )
      create(:sponsors_activity,
        sponsor: other_untrusted_sponsor,
        sponsorable: @untrusted_sponsorable,
        sponsors_tier: tier_above_limit,
      )

      refute Sponsors::TrustSystem.enough_trust_for_sponsorship?(
        actor: @untrusted_sponsor,
        sponsor: @untrusted_sponsor,
        sponsorable: @untrusted_sponsorable,
        tier: one_dollar_tier,
      )
    end

    test "false when both sponsor and sponsorable are untrusted and new tier pushes total above limit for sponsor and feature flag enabled" do
      GitHub.flipper[:sponsors_enforce_trust_system].enable

      other_untrusted_sponsorable = create(:sponsorable_user, :untrusted)
      limit_in_dollars = Sponsors::TrustSystem::SponsorshipCheck::UNTRUSTED_SPONSORSHIP_LIMIT_IN_DOLLARS
      amount_below_limit_in_cents = (limit_in_dollars - 1) * 100
      tier_below_limit = create(:sponsors_tier,
        sponsors_listing: other_untrusted_sponsorable.sponsors_listing,
        monthly_price_in_cents: amount_below_limit_in_cents,
      )
      create(:sponsors_activity,
        sponsor: @untrusted_sponsor,
        sponsorable: other_untrusted_sponsorable,
        sponsors_tier: tier_below_limit,
      )

      refute Sponsors::TrustSystem.enough_trust_for_sponsorship?(
        actor: @untrusted_sponsor,
        sponsor: @untrusted_sponsor,
        sponsorable: @untrusted_sponsorable,
        tier: tier_below_limit,
      )

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.FraudSystemActionProhibited")
      message = hydro_messages(schema: "github.sponsors.v1.FraudSystemActionProhibited").first

      assert_equal @untrusted_sponsor.login, message[:actor][:login]
      assert_equal :CREATE_SPONSORSHIP, message[:action]
      assert_equal :SPONSOR, message[:trust_target]
      assert_equal :UNTRUSTED, message[:trust_level]
      assert_equal @untrusted_sponsor.login, message[:sponsor][:login]
      assert_equal @untrusted_sponsorable.login, message[:sponsorable][:login]
      assert_equal @untrusted_sponsorable.id, message[:listing][:sponsorable_id]
      assert_equal @untrusted_sponsors_listing.id, message[:listing_stafftools_metadata][:sponsors_listing_id]
      assert_equal tier_below_limit.id, message[:tier][:id]
    end

    test "false when untrusted sponsor total is already above limit and feature flag enabled" do
      GitHub.flipper[:sponsors_enforce_trust_system].enable

      limit_in_dollars = Sponsors::TrustSystem::SponsorshipCheck::UNTRUSTED_SPONSORSHIP_LIMIT_IN_DOLLARS
      amount_in_cents = (limit_in_dollars / 2 + 1) * 100
      assert_operator (2 * amount_in_cents) / 100, :>, limit_in_dollars

      untrusted_sponsorable2, untrusted_sponsorable3 = create_list(:sponsorable_user, 2, :untrusted,
        sponsors_tier_count: 0
      )

      create(:sponsors_activity,
        sponsor: @untrusted_sponsor,
        sponsorable: untrusted_sponsorable2,
        sponsors_tier: create(:sponsors_tier,
          sponsorable: untrusted_sponsorable2,
          monthly_price_in_cents: amount_in_cents
        ),
      )
      create(:sponsors_activity,
        sponsor: @untrusted_sponsor,
        sponsorable: untrusted_sponsorable3,
        sponsors_tier: create(:sponsors_tier,
          sponsorable: untrusted_sponsorable3,
          monthly_price_in_cents: amount_in_cents
        ),
      )

      min_tier = create(:sponsors_tier, sponsorable: @untrusted_sponsorable, monthly_price_in_cents: 1_00)

      refute Sponsors::TrustSystem.enough_trust_for_sponsorship?(
        actor: @untrusted_sponsor,
        sponsor: @untrusted_sponsor,
        sponsorable: @untrusted_sponsorable,
        tier: min_tier,
      )
    end

    test "false when untrusted sponsorable total is already above limit and feature flag enabled" do
      GitHub.flipper[:sponsors_enforce_trust_system].enable

      limit_in_dollars = Sponsors::TrustSystem::SponsorshipCheck::UNTRUSTED_SPONSORSHIP_LIMIT_IN_DOLLARS
      amount_in_cents = (limit_in_dollars / 2 + 1) * 100
      assert_operator (2 * amount_in_cents) / 100, :>, limit_in_dollars

      untrusted_sponsor2, untrusted_sponsor3 = create_list(:user, 2)

      min_tier = create(:sponsors_tier,
        sponsorable: @untrusted_sponsorable,
        monthly_price_in_cents: 1_00,
      )
      tier = create(:sponsors_tier,
        sponsorable: @untrusted_sponsorable,
        monthly_price_in_cents: amount_in_cents,
      )

      create(:sponsors_activity,
        sponsor: untrusted_sponsor2,
        sponsorable: @untrusted_sponsorable,
        sponsors_tier: tier,
      )
      create(:sponsors_activity,
        sponsor: untrusted_sponsor3,
        sponsorable: @untrusted_sponsorable,
        sponsors_tier: tier,
      )

      refute Sponsors::TrustSystem.enough_trust_for_sponsorship?(
        actor: @untrusted_sponsor,
        sponsor: @untrusted_sponsor,
        sponsorable: @untrusted_sponsorable,
        tier: min_tier,
      )
    end
  end
end
