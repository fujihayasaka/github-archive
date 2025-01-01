# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DelistSpammySponsorsListingJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @spammer = create(:spammy_user, :verified)
    @sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @spammer)
  end

  if GitHub.sponsors_enabled?
    test "marks approved Sponsors listing as spammy when maintainer is spammy" do
      DelistSpammySponsorsListingJob.perform_now(sponsorable: @spammer)
      assert_predicate @sponsors_listing.reload, :spammy?
    end

    test "marks approved Sponsors listing as spammy when maintainer is suspended" do
      approved_listing = create(:sponsors_listing, :approved)
      suspended_sponsorable = approved_listing.sponsorable
      suspended_sponsorable.suspend("Suspended!")

      DelistSpammySponsorsListingJob.perform_now(sponsorable: suspended_sponsorable)
      assert_predicate approved_listing.reload, :spammy?
    end

    test "enqueues job to disable automatic Stripe payouts when Sponsors listing has an active Stripe account" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @sponsors_listing)

      assert_enqueued_with(
        job: ConfigureStripeAccountJob,
        args: [stripe_account, { freeze_payouts: true, actor: nil, reason: "Spammy maintainer" }],
      ) do
        DelistSpammySponsorsListingJob.perform_now(sponsorable: @spammer)
      end
    end

    test "does not enqueue job to disable automatic Stripe payouts when Sponsors listing has no active Stripe account" do
      assert_nil @sponsors_listing.active_stripe_connect_account
      assert_no_enqueued_jobs only: ConfigureStripeAccountJob do
        DelistSpammySponsorsListingJob.perform_now(sponsorable: @spammer)
      end
    end

    test "will not mark approved Sponsors listing as spammy when maintainer is not spammy" do
      sponsorable = create(:user, :sponsorable)
      listing = sponsorable.sponsors_listing

      DelistSpammySponsorsListingJob.perform_now(sponsorable: sponsorable)

      refute_predicate listing.reload, :spammy?
    end

    test "will not mark non-approved Sponsors listing as spammy even when maintainer is spammy" do
      @sponsors_listing.actor = @spammer
      @sponsors_listing.disable!
      DelistSpammySponsorsListingJob.perform_now(sponsorable: @spammer)
      refute_predicate @sponsors_listing.reload, :spammy?
    end

    test "retries the job on dirty exit" do
      assert_retry_on_dirty_exit(job: DelistSpammySponsorsListingJob, args: [{ sponsorable: @spammer }])
    end

    test "no-op when Sponsors listing is already spammy" do
      spammy_listing = create(:sponsors_listing, :spammy)
      DelistSpammySponsorsListingJob.perform_now(sponsorable: spammy_listing.sponsorable)
      assert_predicate spammy_listing.reload, :spammy?
    end
  else
    test "no-op when Sponsors is disabled" do
      DelistSpammySponsorsListingJob.perform_now(sponsorable: @spammer)
      assert_predicate @sponsors_listing.reload, :approved?
    end
  end
end
