# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::Sponsors::ApproveSponsorsListingsTest < GitHub::TestCase
  fixtures do
    @staff = create(:staff_admin_user)
  end

  if GitHub.sponsors_enabled?
    test "approves the specified Sponsors members" do
      sponsors_listing1 = create(:sponsors_listing, :for_org, :ready_for_approval)
      sponsors_listing2 = create(:sponsors_listing, :ready_for_approval)
      sponsors_listing3 = create(:sponsors_listing, :ready_for_approval_with_custom_amounts)
      old_reviewed_at1 = sponsors_listing1.stafftools_metadata.reviewed_at
      old_reviewed_at2 = sponsors_listing2.stafftools_metadata.reviewed_at
      old_reviewed_at3 = sponsors_listing3.stafftools_metadata.reviewed_at

      result = Stafftools::Sponsors::ApproveSponsorsListings.call(
        sponsorable_logins: [sponsors_listing1.sponsorable_login, sponsors_listing3.sponsorable_login],
        actor: @staff,
      )

      assert_predicate result, :success?
      assert_equal "Approved 2 GitHub Sponsors maintainers.", result.message

      assert_predicate sponsors_listing1.reload, :approved?
      refute_nil sponsors_listing1.reload_stafftools_metadata.reviewed_at
      refute_equal old_reviewed_at1, sponsors_listing1.stafftools_metadata.reviewed_at
      refute_nil sponsors_listing1.published_at

      refute_predicate sponsors_listing2.reload, :approved?, "should not have approved listing that was not specified"
      assert_equal old_reviewed_at2, sponsors_listing2.reload_stafftools_metadata.reviewed_at
      assert_nil sponsors_listing2.published_at

      assert_predicate sponsors_listing3.reload, :approved?
      refute_nil sponsors_listing3.reload_stafftools_metadata.reviewed_at
      refute_equal old_reviewed_at3, sponsors_listing3.stafftools_metadata.reviewed_at
      refute_nil sponsors_listing3.published_at
    end

    test "handles when specified maintainer does not have a listing ready for approval" do
      listing = create(:sponsors_listing, :pending_approval, :with_stripe_account)

      result = Stafftools::Sponsors::ApproveSponsorsListings.call(
        sponsorable_logins: [listing.sponsorable_login],
        actor: @staff,
      )

      refute_predicate result, :success?
      assert_equal "Failed to approve 1 GitHub Sponsors maintainer.", result.message
      refute_predicate listing.reload, :approved?
      assert_nil listing.published_at
    end

    test "handles when some approvals succeed and some do not" do
      listing_that_will_succeed = create(:sponsors_listing, :for_org, :ready_for_approval_with_custom_amounts)
      listing_that_will_fail = create(:sponsors_listing, :pending_approval, :with_stripe_account)

      result = Stafftools::Sponsors::ApproveSponsorsListings.call(
        sponsorable_logins: [listing_that_will_fail.sponsorable_login, listing_that_will_succeed.sponsorable_login],
        actor: @staff,
      )

      refute_predicate result, :success?
      assert_equal "Failed to approve 1 GitHub Sponsors maintainer. Approved 1 GitHub Sponsors maintainer.",
        result.message
      refute_predicate listing_that_will_fail.reload, :approved?
      assert_nil listing_that_will_fail.published_at
      assert_predicate listing_that_will_succeed.reload, :approved?
      refute_nil listing_that_will_succeed.published_at
    end

    test "limits how many maintainers can be approved at once" do
      limit = 2
      sponsors_listings = create_list(:sponsors_listing, limit + 1, :ready_for_approval)

      Stafftools::Sponsors::ApproveSponsorsListings.stub_const(:MAX_SPONSORABLES, limit) do
        result = Stafftools::Sponsors::ApproveSponsorsListings.call(
          sponsorable_logins: sponsors_listings.map(&:sponsorable_login),
          actor: @staff,
        )

        refute_predicate result, :success?
        assert_equal "Please specify #{limit} maintainers or fewer to approve at a time.", result.message
        sponsors_listings.each do |sponsors_listing|
          refute_predicate sponsors_listing.reload, :approved?
        end
      end
    end
  else
    test "no-op when Sponsors is disabled" do
      sponsors_listing = create(:sponsors_listing, :ready_for_approval)

      result = Stafftools::Sponsors::ApproveSponsorsListings.call(
        sponsorable_logins: [sponsors_listing.sponsorable_login],
        actor: @staff,
      )

      refute_predicate result, :success?
      assert_equal "GitHub Sponsors is not enabled.", result.message
      refute_predicate sponsors_listing.reload, :approved?
    end
  end
end
