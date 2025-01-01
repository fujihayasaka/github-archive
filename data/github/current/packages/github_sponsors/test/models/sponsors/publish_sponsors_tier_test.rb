# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsPublishSponsorsTierTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @sponsors_listing = create(:sponsors_listing, :approved, tier_count: 1)
    @sponsorable = @sponsors_listing.sponsorable
  end

  context "sponsors tier publishing" do
    test "sponsorable publishes a draft tier" do
      draft_tier = create(:sponsors_tier, :draft, sponsors_listing: @sponsors_listing)

      Sponsors::PublishSponsorsTier.call(tier: draft_tier, viewer: @sponsorable)

      assert_predicate draft_tier.reload, :published?
      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@sponsorable),
        listing: Hydro::EntitySerializer.sponsors_listing(@sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(draft_tier),
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.TierPublish")
    end

    test "org owner publishes a draft tier" do
      org = create(:organization)
      listing = create(:sponsors_listing, sponsorable: org)
      tier = create(:sponsors_tier, :draft, sponsors_listing: listing)

      Sponsors::PublishSponsorsTier.call(tier: tier, viewer: org.admin)

      assert_predicate tier.reload, :published?
      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(org.admin),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        tier: Hydro::EntitySerializer.sponsors_tier(tier),
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.TierPublish")
    end

    test "raises error if non-sponsorable publishes a draft tier" do
      other_user = create(:user)
      tier = create(:sponsors_tier, :draft, sponsors_listing: @sponsors_listing)

      error = assert_raises Sponsors::PublishSponsorsTier::ForbiddenError do
        Sponsors::PublishSponsorsTier.call(tier: tier, viewer: other_user)
      end
      assert_equal "#{other_user.login} does not have permission to change the tier.", error.message
    end

    test "raises error for an already published tier" do
      tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing)

      error = assert_raises Sponsors::PublishSponsorsTier::UnprocessableError do
        Sponsors::PublishSponsorsTier.call(tier: tier, viewer: @sponsorable)
      end
      assert_equal "This tier has already been published.", error.message
    end

    test "raises error for a custom tier" do
      tier = create(:sponsors_tier, :custom, sponsors_listing: @sponsors_listing)

      error = assert_raises Sponsors::PublishSponsorsTier::UnprocessableError do
        Sponsors::PublishSponsorsTier.call(tier: tier, viewer: @sponsorable)
      end
      assert_equal "This tier cannot be published.", error.message
    end

    test "raises error for a retired tier" do
      tier = create(:sponsors_tier, :retired, sponsors_listing: @sponsors_listing)

      error = assert_raises Sponsors::PublishSponsorsTier::UnprocessableError do
        Sponsors::PublishSponsorsTier.call(tier: tier, viewer: @sponsorable)
      end
      assert_equal "This tier has been retired.", error.message
    end

    test "raises error for a banned listing" do
      banned_listing = create(:sponsors_listing, :banned)
      tier = create(:sponsors_tier, :draft, sponsors_listing: banned_listing)

      error = assert_raises Sponsors::PublishSponsorsTier::ForbiddenError do
        Sponsors::PublishSponsorsTier.call(tier: tier, viewer: banned_listing.sponsorable)
      end
      assert_equal "Tiers for this Sponsors profile cannot be published at this time.", error.message
    end

    test "raises error if published tier limit reached" do
      SponsorsTier.stub_const(:PUBLISHED_TIER_LIMIT_PER_FREQUENCY, 1) do
        tier = create(:sponsors_tier, :draft, sponsors_listing: @sponsors_listing)

        error = assert_raises Sponsors::PublishSponsorsTier::UnprocessableError do
          Sponsors::PublishSponsorsTier.call(tier: tier, viewer: @sponsorable)
        end
        assert_equal "The Sponsors profile has reached the limit of published, monthly tiers.", error.message
      end
    end
  end
end unless GitHub.enterprise?
