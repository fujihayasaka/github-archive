# typed: true
# frozen_string_literal: true

require "test_helper"

class CancelPatreonSponsorshipsTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @sponsorable = create(:user, :verified)
    @listing = create(:sponsors_listing, :approved, sponsorable: @sponsorable, tier_count: 0)
    @spu = create(:sponsors_patreon_user, :with_tier, user: @sponsorable)
  end

  context ".call" do
    if GitHub.sponsors_enabled?
      test "records how long it takes to cancel sponsorships" do
        actor = create(:user)
        CancelPatreonSponsorships.call(sponsors_patreon_user: @spu, sponsorships_to_cancel: [], actor: actor)
        assert_dogstats_timing(1, "#{CancelPatreonSponsorships::DATADOG_PREFIX}.cancel_sponsorships")
      end

      test "cancels sponsorship for inactive Patreon membership" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor)
        sponsorship = create(:sponsorship, :patreon, sponsor: sponsor_spu.user, sponsorable: @sponsorable)

        assert_no_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CancelPatreonSponsorships.call(sponsors_patreon_user: @spu, sponsorships_to_cancel: [sponsorship],
            actor: sponsor_spu.user)
        end

        refute_predicate sponsorship.reload, :active?
      end

      test "does not cancel sponsorship for inactive Patreon membership when write_mode=false" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor)
        sponsor = sponsor_spu.user
        freeze_time
        sponsorship = create(:sponsorship, :patreon, sponsor: sponsor, sponsorable: @sponsorable)

        assert_logged(
          Body: "Would cancel Patreon sponsorship",
          "actor.id": sponsor.id,
          "gh.catalog_service": "github/github_sponsors",
          "code.namespace": "CancelPatreonSponsorships",
          "code.function": "cancel_sponsorships",
          "sponsorable.id": @sponsorable.id,
          "sponsor.id": sponsor.id,
          "sponsorship.id": sponsorship.id,
          "sponsorship.tier_selected_on": Time.now.to_date.iso8601,
        ) do
          assert_no_difference(["Sponsorship.count", "SponsorsTier.count"]) do
            CancelPatreonSponsorships.call(sponsors_patreon_user: @spu, sponsorships_to_cancel: [sponsorship],
              actor: sponsor, write_mode: false)
          end
        end

        assert_predicate sponsorship.reload, :active?
      end

      test "instruments sponsorship cancel request to Hydro" do
        sponsor_spu = create(:sponsors_patreon_user, :sponsor)
        sponsorship = create(:sponsorship, :patreon, sponsor: sponsor_spu.user, sponsorable: @sponsorable)

        assert_no_difference(["Sponsorship.count", "SponsorsTier.count"]) do
          CancelPatreonSponsorships.call(sponsors_patreon_user: @spu, sponsorships_to_cancel: [sponsorship],
            actor: sponsor_spu.user)
        end

        refute_predicate sponsorship.reload, :active?

        expected_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
          tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
          listing: Hydro::EntitySerializer.sponsors_listing(sponsorship.sponsors_listing),
          listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
            sponsorship.sponsors_listing_stafftools_metadata,
          ),
          actor: Hydro::EntitySerializer.user(sponsorship.sponsor),
          sponsor: Hydro::EntitySerializer.user(sponsorship.sponsor),
          sponsorable: Hydro::EntitySerializer.user(sponsorship.sponsorable),
          reason: :SPONSOR_INITIATED,
          forced: true,
        }
        assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      end

      test "raises when given a sponsorship for a maintainer different than the one specified" do
        sponsorship = create(:sponsorship, :patreon)
        refute_equal sponsorship.sponsorable, @spu.user

        error = assert_raises(CancelPatreonSponsorships::UnprocessableError) do
          CancelPatreonSponsorships.call(sponsors_patreon_user: @spu, sponsorships_to_cancel: [sponsorship])
        end

        assert_equal "Sponsorship is not for @#{@sponsorable}", error.message
      end

      test "raises when given a non-Patreon sponsorship" do
        sponsorship = create(:sponsorship, sponsorable: @sponsorable)
        refute_predicate sponsorship, :patreon?

        error = assert_raises(CancelPatreonSponsorships::UnprocessableError) do
          CancelPatreonSponsorships.call(sponsors_patreon_user: @spu, sponsorships_to_cancel: [sponsorship])
        end

        assert_equal "Sponsorship is not through Patreon", error.message
      end
    else
      test "raises when Sponsors is disabled" do
        error = assert_raises(CancelPatreonSponsorships::UnprocessableError) do
          CancelPatreonSponsorships.call(sponsors_patreon_user: @spu, sponsorships_to_cancel: [])
        end
        assert_equal "GitHub Sponsors is not enabled", error.message
      end
    end
  end
end
