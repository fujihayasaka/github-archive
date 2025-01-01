# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateAndUpdatePatreonSponsorshipsTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @sponsorable = create(:user, :verified)
    @listing = create(:sponsors_listing, :approved, sponsorable: @sponsorable, tier_count: 0)
    @spu = create(:sponsors_patreon_user, :with_tier, user: @sponsorable)
  end

  context ".call" do
    if GitHub.sponsors_enabled?
      test "records how long it takes to create and update sponsorships" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_dogstats_timing(1, "#{SponsorsPatreonClient::DATADOG_PREFIX}.get_memberships",
          tags: ["max_pages:5", "first_batch:true"])

        CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data, actor: sponsor_spu.user)

        assert_dogstats_timing(1, "#{CreateAndUpdatePatreonSponsorships::DATADOG_PREFIX}.create_sponsorships")
        assert_dogstats_timing(1, "#{CreateAndUpdatePatreonSponsorships::DATADOG_PREFIX}.update_sponsorships")
      end

      test "creates sponsorships that don't exist for active Patreon memberships when sponsor has linked with Patreon" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        actor = sponsor_spu.user

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_equal({ actor.id => 100 }, data.target_sponsorship_cents_by_sponsor_id)
        assert_empty data.membership_next_page_cursors_by_campaign_id
        refute_predicate data, :has_another_page_of_memberships?

        assert_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data, actor: actor)
        end

        sponsorship = actor.active_sponsorships_as_sponsor_relation.find_by(sponsorable_id: @sponsorable.id)
        refute_nil sponsorship
        assert_nil sponsorship.subscription_item
        assert_predicate sponsorship, :patreon?
        tier = @listing.sponsors_tiers.with_custom_state.last
        refute_nil tier
        assert_equal actor, tier.creator
        assert_equal tier, sponsorship.tier
        assert_equal 100, tier.monthly_price_in_cents
        assert_equal "Patreon membership", tier.description
        refute_predicate sponsorship, :is_sponsor_opted_in_to_email?
      end

      test "creates sponsorships based on current results as well as given active-patron data" do
        some_other_sponsor = create(:sponsors_patreon_user, :sponsor).user
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        actor = sponsor_spu.user

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(
            sponsors_patreon_user: @spu,
            target_sponsorship_cents_by_sponsor_id: { some_other_sponsor.id => 500 },
          )
        end

        assert_equal({ some_other_sponsor.id => 500, actor.id => 100 },
          data.target_sponsorship_cents_by_sponsor_id)
        assert_empty data.membership_next_page_cursors_by_campaign_id
        refute_predicate data, :has_another_page_of_memberships?

        assert_difference("Sponsorship.count", 2) do
          assert_difference("SponsorsTier.count", 2) do
            CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data, actor: actor)
          end
        end

        sponsorship1 = actor.active_sponsorships_as_sponsor_relation.find_by(sponsorable_id: @sponsorable.id)
        refute_nil sponsorship1
        assert_nil sponsorship1.subscription_item
        assert_predicate sponsorship1, :patreon?
        tier1 = @listing.sponsors_tiers.with_custom_state.where(creator_id: actor.id).last
        refute_nil tier1
        assert_equal tier1, sponsorship1.tier
        assert_nil tier1.parent_tier
        assert_equal 100, tier1.monthly_price_in_cents
        assert_equal "Patreon membership", tier1.description
        refute_predicate sponsorship1, :is_sponsor_opted_in_to_email?

        sponsorship2 = some_other_sponsor.active_sponsorships_as_sponsor_relation
          .find_by(sponsorable_id: @sponsorable.id)
        refute_nil sponsorship2
        assert_nil sponsorship2.subscription_item
        assert_predicate sponsorship2, :patreon?
        tier2 = @listing.sponsors_tiers.with_custom_state.where(creator_id: some_other_sponsor.id).last
        refute_nil tier2
        assert_equal tier2, sponsorship2.tier
        assert_nil tier2.parent_tier
        assert_equal 500, tier2.monthly_price_in_cents
        assert_equal "Patreon membership", tier2.description
        refute_predicate sponsorship2, :is_sponsor_opted_in_to_email?
      end

      test "fetches Patreon memberships from the specified page for campaign" do
        cursor = "02B9AS9r0rVy7smJCVpWQPdNob"
        campaign_id = "459978"
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        actor = sponsor_spu.user

        # Shouldn't load the list of all campaigns because we're specifying particular campaigns to load, via
        # `membership_page_cursors_by_campaign_id`
        SponsorsPatreonClient.any_instance.expects(:get_monthly_campaigns).never

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(
            sponsors_patreon_user: @spu,
            membership_page_cursors_by_campaign_id: { campaign_id => cursor },
            max_membership_pages: 4,
          )
        end

        assert_no_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data, actor: actor)
        end
      end

      test "respects given max membership pages parameter" do
        campaign_id = "459978"
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        actor = sponsor_spu.user

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu, max_membership_pages: 1)
        end

        assert_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data, actor: actor)
        end
      end

      # https://github.com/github/sponsors/issues/5307
      test "creates sponsorships for org sponsor" do
        org_admin = create(:user, :verified)
        org_sponsor = create(:credit_card_organization, admin: org_admin, plan: GitHub::Plan.free)
        # See patron ID in VCR cassette:
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, user: org_sponsor, patreon_user_id: "31189703")

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data, actor: org_admin)
        end

        sponsorship = org_sponsor.active_sponsorships_as_sponsor_relation.find_by(sponsorable_id: @sponsorable.id)
        refute_nil sponsorship
        assert_nil sponsorship.subscription_item
        assert_predicate sponsorship, :patreon?
        tier = @listing.sponsors_tiers.with_custom_state.last
        refute_nil tier
        assert_equal org_sponsor, tier.creator
        assert_equal tier, sponsorship.tier
        assert_nil tier.parent_tier
        assert_equal 100, tier.monthly_price_in_cents
        assert_equal "Patreon membership", tier.description
        refute_predicate sponsorship, :is_sponsor_opted_in_to_email?
      end

      # https://github.com/github/sponsors/issues/5379
      test "does not try to use existing one-time tier with the same amount" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        one_time_tier = create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 100,
          sponsors_listing: @listing)
        assert_includes @spu.sponsors_listing.published_sponsors_tiers.reload, one_time_tier

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)
        end

        sponsorship = sponsor_spu.user.active_sponsorships_as_sponsor_relation
          .find_by(sponsorable_id: @sponsorable.id)
        refute_nil sponsorship
        assert_nil sponsorship.subscription_item
        assert_predicate sponsorship, :patreon?
        tier = @listing.sponsors_tiers.with_custom_state.last
        refute_nil tier
        assert_equal tier, sponsorship.tier
        assert_equal 100, tier.monthly_price_in_cents
        assert_nil tier.parent_tier
        assert_equal "Patreon membership", tier.description
        refute_predicate sponsorship, :is_sponsor_opted_in_to_email?
      end

      test "sets parent tier on the new custom tier when one exists and feature is enabled" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "45391621") # patron ID in cassette
        sponsor = sponsor_spu.user
        published_tier = create(:sponsors_tier, :published, sponsors_listing: @listing,
          monthly_price_in_cents: 35_00) # patron has a $40 pledge in the cassette
        sponsor.enable_feature(:sponsors_patreon_parent_tiers)

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)
        end

        sponsorship = sponsor.active_sponsorships_as_sponsor_relation.find_by(sponsorable_id: @sponsorable.id)
        refute_nil sponsorship
        assert_nil sponsorship.subscription_item
        assert_predicate sponsorship, :patreon?
        tier = @listing.sponsors_tiers.with_custom_state.last
        refute_nil tier
        assert_equal tier, sponsorship.tier
        assert_equal 40_00, tier.monthly_price_in_cents
        assert_equal published_tier, tier.parent_tier
        assert_equal "Patreon membership", tier.description
      end

      test "does not set parent tier on the new custom tier when one exists but feature is disabled" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "45391621") # patron ID in cassette
        sponsor = sponsor_spu.user
        published_tier = create(:sponsors_tier, :published, sponsors_listing: @listing,
          monthly_price_in_cents: 35_00) # patron has a $40 pledge in the cassette
        GitHub.flipper[:sponsors_patreon_parent_tiers].disable

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)
        end

        sponsorship = sponsor.active_sponsorships_as_sponsor_relation.find_by(sponsorable_id: @sponsorable.id)
        refute_nil sponsorship
        assert_nil sponsorship.subscription_item
        assert_predicate sponsorship, :patreon?
        tier = @listing.sponsors_tiers.with_custom_state.last
        refute_nil tier
        assert_equal tier, sponsorship.tier
        assert_equal 40_00, tier.monthly_price_in_cents
        assert_nil tier.parent_tier
        assert_equal "Patreon membership", tier.description
      end

      # https://github.com/github/sponsors/issues/5393
      test "does not try to create a tier for $0 when there is an inactive membership" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor)
        SponsorsPatreonClient.any_instance.expects(:get_monthly_campaigns).once.returns([{
          "attributes" => { "is_monthly" => true },
          "id" => @spu.patreon_campaign_ids.first,
          "relationships" => { "tiers" => { "data" => [{ "id" => "sometierid", "type" => "tier" }] } },
          "included" => [{
            "attributes" => { "amount_cents" => 100, "published" => true }, "id" => "sometierid", "type" => "tier",
          }],
        }])
        SponsorsPatreonClient.any_instance.expects(:get_all_pages).once.returns({
          "data" => [{
            "attributes" => { "currently_entitled_amount_cents" => 0, "patron_status" => "former_patron" },
            "id" => "somemembershipid",
            "relationships" => {
              "currently_entitled_tiers" => { "data" => [] },
              "user" => {
                "data" => { "id" => sponsor_spu.patreon_user_id, "type" => "user" },
                "links" => { "related" => "https://www.patreon.com/api/oauth2/v2/user/619786" },
              },
            },
            "type" => "member",
          }],
          "included" => [{ "attributes" => {}, "id" => sponsor_spu.patreon_user_id, "type" => "user" }],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        data = SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)

        assert_no_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data, actor: sponsor_spu.user)
        end
      end

      test "does not create sponsorships that don't exist if enabled_as_sponsorable field is false" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette

        @spu.update(enabled_as_sponsorable: false)

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_no_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data, actor: sponsor_spu.user)
        end

        sponsorship = sponsor_spu.user.active_sponsorships_as_sponsor_relation
          .find_by(sponsorable_id: @sponsorable.id)
        assert_nil sponsorship
      end

      test "emits hydro event when sponsorship is created" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette

        reset_hydro

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data, actor: sponsor_spu.user)
        end

        sponsorship = sponsor_spu.user.active_sponsorships_as_sponsor_relation
          .find_by(sponsorable_id: @sponsorable.id)

        message = {
          request_context: nil,
          sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
          listing: Hydro::EntitySerializer.sponsors_listing(@listing),
          tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
          listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
            @listing.stafftools_metadata,
          ),
          payment_source: :PATREON,
        }

        assert_hydro_published_partial(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      end

      test "updates sponsorship that exists for active Patreon memberships when sponsor has linked with Patreon and amount changed" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        old_tier = create(:sponsors_tier, :published, sponsors_listing: @listing, monthly_price_in_cents: 18_00)
        patreon_sponsor = sponsor_spu.user
        sponsorship = create(:sponsorship, :patreon, sponsorable: @sponsorable, sponsor: patreon_sponsor,
          tier: old_tier)

        assert_equal 1800, sponsorship.reload.monthly_price_in_cents

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_difference("SponsorsTier.count") do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data, actor: patreon_sponsor)
        end

        tier = @listing.sponsors_tiers.with_custom_state.last
        assert_equal 100, tier.monthly_price_in_cents
        assert_equal tier, sponsorship.reload.tier
        assert_equal 100, sponsorship.monthly_price_in_cents
        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipTierChange")
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(patreon_sponsor),
          sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
          listing: Hydro::EntitySerializer.sponsors_listing(@listing),
          previous_tier: Hydro::EntitySerializer.sponsors_tier(old_tier),
          current_tier: Hydro::EntitySerializer.sponsors_tier(tier),
        }, schema: "github.sponsors.v1.SponsorshipTierChange")
      end

      test "does NOT emit hydro event when sponsorship updated" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        tier = create(:sponsors_tier, :published, sponsors_listing: @listing, monthly_price_in_cents: 18_00)
        sponsorship = create(:sponsorship, :patreon, sponsorable: @sponsorable, sponsor: sponsor_spu.user, tier: tier)

        assert_equal 1800, sponsorship.reload.monthly_price_in_cents

        reset_hydro

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_difference("SponsorsTier.count") do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)
        end

        refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCreateCancel")
      end

      test "raises when listing is in draft state" do
        listing = create(:sponsors_listing)
        unapproved_sponsorable = listing.sponsorable
        spu = create(:sponsors_patreon_user, user: unapproved_sponsorable)
        data = SponsorsPatreonSponsorshipLoader::Result.empty

        assert_raises_with_message(CreateAndUpdatePatreonSponsorships::UnprocessableError,
          "Given account cannot be sponsored on GitHub Sponsors") do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: spu, data: data)
        end
      end

      test "raises when creating the sponsorship fails" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        sponsor = sponsor_spu.user
        @sponsorable.block(sponsor)

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_no_difference("Sponsorship.count") do
          error = assert_raises(CreateAndUpdatePatreonSponsorships::UnprocessableError) do
            CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)
          end

          assert_equal "Could not create @#{sponsor}'s sponsorship of @#{@sponsorable}: You can't perform that " \
            "action at this time.", error.message
        end
      end

      test "raises when creating the tier fails due to not meeting maintainer's minimum amount" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "55160") # patron ID in cassette
        sponsor = sponsor_spu.user
        assert_nil @listing.published_sponsors_tiers.recurring.find_by(monthly_price_in_cents: 8_00),
          "need no published tier at the target amount to exist"

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        @listing.update!(min_custom_tier_amount_in_cents: 9_00) # pledge for $8.00 in cassette
        @spu.reload_sponsors_listing

        assert_no_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          error = assert_raises(CreateAndUpdatePatreonSponsorships::UnprocessableError) do
            CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)
          end

          assert_equal "Could not create tier for @#{sponsor}'s sponsorship of @#{@sponsorable}: " \
            "Could not create custom tier $8 a month: Monthly price must be at least $9", error.message
        end
      end

      # https://github.com/github/sponsors/issues/5247
      test "restarting a sponsorship previously paid on GitHub and now paid on Patreon updates sponsorship" do
        sponsor = create(:verified_user)
        sponsorship = create(:sponsorship, sponsor: sponsor, sponsorable: @sponsorable, monthly_price_in_cents: 200)
        old_tier = sponsorship.tier
        assert_equal 200, old_tier.monthly_price_in_cents

        perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
          result = sponsorship.cancel(actor: sponsor)
          assert result.success
        end
        refute_predicate sponsorship.reload, :active?
        assert_predicate sponsorship, :github?

        spu = create(:sponsors_patreon_user, user: sponsor, patreon_user_id: "31189703") # patron ID in cassette

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)

        assert_predicate sponsorship.reload, :patreon?
        assert_predicate sponsorship, :active?
        tier = @listing.sponsors_tiers.last
        refute_equal tier, old_tier
        refute_nil tier
        assert_equal tier, sponsorship.tier
        assert_equal 100, tier.monthly_price_in_cents
      end

      test "restarting a sponsorship previously paid on Patreon and now paid on GitHub updates sponsorship" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        tier = create(:sponsors_tier, :published, sponsors_listing: @listing, monthly_price_in_cents: 18_00)
        sponsorship = create(:sponsorship, :patreon, sponsorable: @sponsorable, sponsor: sponsor_spu.user, tier: tier)

        perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
          result = sponsorship.cancel(actor: User.staff_user)
          assert result.success
        end
        refute_predicate sponsorship.reload, :active?
        assert_predicate sponsorship, :patreon?

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)

        assert_predicate sponsorship.reload, :patreon?
        assert_predicate sponsorship, :active?
        tier = @listing.sponsors_tiers.last
        refute_nil tier
        assert_equal tier, sponsorship.tier
        assert_equal 100, tier.monthly_price_in_cents
      end

      test "it does NOT create a sponsorship for trade restricted users" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        sponsor_spu.user.trade_controls_restriction.full!

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_no_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)
        end

        sponsorship = sponsor_spu.user.active_sponsorships_as_sponsor_relation
          .find_by(sponsorable_id: @sponsorable.id)
        assert_nil sponsorship
      end

      # https://github.com/github/sponsors/issues/5248
      test "does not modify a non-Patreon GitHub sponsorship when a sponsorship is created on Patreon" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: sponsor_spu.user)
        tier = sponsorship.tier

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        assert_no_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)
        end

        sponsorship = sponsor_spu.user.active_sponsorships_as_sponsor_relation
          .find_by(sponsorable_id: @sponsorable.id)
        refute_nil sponsorship
        refute_nil sponsorship.subscription_item
        refute_predicate sponsorship, :patreon?
        assert_equal tier, sponsorship.tier
      end

      # https://github.com/github/sponsors/issues/5248
      test "does not modify a non-Patreon GitHub sponsorship when a sponsorship is updated on Patreon" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
        tier = create(:sponsors_tier, :published, sponsors_listing: @listing, monthly_price_in_cents: 18_00)
        sponsorship = create(:sponsorship,
          sponsorable: @sponsorable,
          sponsor: sponsor_spu.user,
          tier: tier
        )

        assert_equal 1800, sponsorship.reload.monthly_price_in_cents

        data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
        end

        CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)

        refute_predicate sponsorship, :patreon?
        assert_equal 1800, sponsorship.reload.monthly_price_in_cents
        assert_equal tier, sponsorship.reload.tier
      end
    else
      test "raises when Sponsors is disabled" do
        data = SponsorsPatreonSponsorshipLoader::Result.empty
        error = assert_raises(CreateAndUpdatePatreonSponsorships::UnprocessableError) do
          CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: @spu, data: data)
        end
        assert_equal "GitHub Sponsors is not enabled", error.message
      end
    end
  end
end
