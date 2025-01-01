# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::Sponsors::BanSponsorsListingsTest < GitHub::TestCase
  fixtures do
    @staff = create(:staff_admin_user)
  end

  if GitHub.sponsors_enabled?
    test "bans the specified Sponsors members" do
      sponsors_listing1 = create(:sponsors_listing, :for_org)
      sponsors_listing2 = create(:sponsors_listing)
      sponsors_listing3 = create(:sponsors_listing)

      assert_enqueued_with(
        job: BanSponsorsListingJob,
        args: [{ sponsors_listing: sponsors_listing1, actor: @staff, ban_reason: "fraud" }],
      ) do
        assert_enqueued_with(
          job: BanSponsorsListingJob,
          args: [{ sponsors_listing: sponsors_listing3, actor: @staff, ban_reason: "fraud" }],
        ) do
          result = Stafftools::Sponsors::BanSponsorsListings.call(
            sponsorable_logins: [sponsors_listing1.sponsorable_login, sponsors_listing3.sponsorable_login],
            ban_reason: "fraud",
            actor: @staff,
          )

          assert_predicate result, :success?
          assert_equal "Scheduled 2 GitHub Sponsors maintainers to be banned soon.", result.message
        end
      end
    end

    test "limits how many maintainers can be banned at once" do
      limit = 2
      sponsors_listings = create_list(:sponsors_listing, limit + 1)

      Stafftools::Sponsors::BanSponsorsListings.stub_const(:MAX_SPONSORABLES, limit) do
        result = Stafftools::Sponsors::BanSponsorsListings.call(
          sponsorable_logins: sponsors_listings.map(&:sponsorable_login),
          ban_reason: "fraud",
          actor: @staff,
        )

        refute_predicate result, :success?
        assert_equal "Please specify #{limit} maintainers or fewer to ban at a time.", result.message
        sponsors_listings.each do |sponsors_listing|
          refute_predicate sponsors_listing.reload, :banned?
        end
      end
    end
  else
    test "no-op when Sponsors is disabled" do
      sponsors_listing = create(:sponsors_listing)

      result = Stafftools::Sponsors::BanSponsorsListings.call(
        sponsorable_logins: [sponsors_listing.sponsorable_login],
        ban_reason: "fraud",
        actor: @staff,
      )

      refute_predicate result, :success?
      assert_equal "GitHub Sponsors is not enabled.", result.message
      refute_predicate sponsors_listing.reload, :banned?
    end
  end
end
