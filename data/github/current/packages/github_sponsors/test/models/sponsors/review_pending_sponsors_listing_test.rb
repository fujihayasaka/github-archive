# typed: true
# frozen_string_literal: true

require "test_helper"

class ReviewPendingSponsorsListingTest < GitHub::TestCase
  fixtures do
    @sponsorable = create(:verified_user, created_at: 2.years.ago)
    @sponsors_listing = create(:sponsors_listing,
      :pending_approval, :with_w8_or_w9_verified_stripe_account,
      sponsorable: @sponsorable, created_at: 2.years.ago
    )

    @public_repo = create(:repository, owner: @sponsors_listing.sponsorable, from_example: :repository_test_simple)
  end

  context "reject result" do
    test "rejects listing with no stripe account" do
      listing = create(:sponsors_listing, :pending_approval)

      assert_nil listing.active_stripe_connect_account

      result = Sponsors::ReviewPendingSponsorsListing.call(sponsors_listing: listing)

      refute_predicate result, :approve?
      assert_equal "Stripe connect account is missing or unverified.", result.error
    end

    test "rejects listing with unrequested stripe w8 or w9 info" do
      listing = create(:sponsors_listing, :pending_approval, :with_w8_or_w9_not_requested_stripe_account)

      result = Sponsors::ReviewPendingSponsorsListing.call(sponsors_listing: listing)

      refute_predicate result, :approve?
      assert_equal "Stripe connect account is missing or unverified.", result.error
    end

    test "rejects listing with unverified stripe w8 or w9 info" do
      listing = create(:sponsors_listing, :pending_approval, :with_w8_or_w9_requested_but_unverified_stripe_account)

      result = Sponsors::ReviewPendingSponsorsListing.call(sponsors_listing: listing)

      refute_predicate result, :approve?
      assert_equal "Stripe connect account is missing or unverified.", result.error
    end

    test "rejects listing older than a year if they have no contributions" do
      listing = create(:sponsors_listing,
        :pending_approval, :with_w8_or_w9_verified_stripe_account, created_at: 2.years.ago
      )

      result = Sponsors::ReviewPendingSponsorsListing.call(sponsors_listing: listing)

      refute_predicate result, :approve?
      assert_equal "Listing does not meet the minimum requirements.", result.error
    end

    test "rejects listing with abuse reports and not enough activity" do
      sponsorable = create(:verified_user, created_at: 6.months.ago)
      create(:abuse_report, :user_report, reported_user: sponsorable)

      listing = create(:sponsors_listing, :ready_for_approval, sponsorable: sponsorable)

      create(:public_repository, owner: sponsorable)
      create(:sponsorship, sponsor: sponsorable)

      result = Sponsors::ReviewPendingSponsorsListing.call(sponsors_listing: listing)

      refute_predicate result, :approve?
    end
  end

  context "approve result" do
    test "approves listing older than a year with many public contributions" do
      create(:commit_contribution, :with_summaries, user: @sponsorable, repository: @public_repo,
        commit_count: 240, committed_date: 6.months.ago
      )

      create_list(:pull_request, 10, :with_mergeable_head, :merged, repository: @public_repo, user: @sponsorable)

      result = Sponsors::ReviewPendingSponsorsListing.call(sponsors_listing: @sponsors_listing)

      assert_predicate result, :approve?
    end

    test "approves listing younger than a year with public repo and published tiers and sponsorships created" do
      sponsorable = create(:verified_user, created_at: 6.months.ago)
      listing = create(:sponsors_listing, :ready_for_approval, sponsorable: sponsorable)

      create(:public_repository, owner: sponsorable)
      create(:sponsorship, sponsor: sponsorable)

      result = Sponsors::ReviewPendingSponsorsListing.call(sponsors_listing: listing)

      assert_predicate result, :approve?
    end

    test "approves listing younger than a year with some public contributions, published tiers, and public repos" do
      sponsorable = create(:verified_user, created_at: 6.months.ago)
      listing = create(:sponsors_listing, :ready_for_approval, sponsorable: sponsorable)

      repo = create(:public_repository, owner: sponsorable,)

      create(:commit_contribution, :with_summaries, user: sponsorable, repository: repo, commit_count: 25, committed_date: 1.day.ago)

      result = Sponsors::ReviewPendingSponsorsListing.call(sponsors_listing: listing)

      assert_predicate result, :approve?
    end
  end
end
