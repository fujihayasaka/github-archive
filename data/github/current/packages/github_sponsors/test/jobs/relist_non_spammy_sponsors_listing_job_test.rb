# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RelistNonSpammySponsorsListingJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @non_spammer = create(:user, :verified)
    @sponsors_listing = create(:sponsors_listing, :spammy, sponsorable: @non_spammer)
  end

  if GitHub.sponsors_enabled?
    test "marks spammy Sponsors listing as approved when maintainer is not spammy" do
      RelistNonSpammySponsorsListingJob.perform_now(sponsorable: @non_spammer)
      assert_predicate @sponsors_listing.reload, :approved?
    end

    test "enqueues job to enable automatic Stripe payouts when Sponsors listing has an active Stripe account" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @sponsors_listing)

      assert_enqueued_with(
        job: ConfigureStripeAccountJob,
        args: [stripe_account, { freeze_payouts: false, actor: nil }],
      ) do
        RelistNonSpammySponsorsListingJob.perform_now(sponsorable: @non_spammer)
      end
    end

    test "does not enqueue job to enable automatic Stripe payouts when Sponsors listing has no active Stripe account" do
      assert_nil @sponsors_listing.active_stripe_connect_account
      assert_no_enqueued_jobs only: ConfigureStripeAccountJob do
        RelistNonSpammySponsorsListingJob.perform_now(sponsorable: @non_spammer)
      end
    end

    test "will not mark spammy Sponsors listing as approved when maintainer is spammy" do
      spammy_listing = create(:sponsors_listing, :spammy)
      sponsorable = spammy_listing.sponsorable
      assert_predicate sponsorable, :spammy?

      RelistNonSpammySponsorsListingJob.perform_now(sponsorable: sponsorable)

      refute_predicate spammy_listing.reload, :approved?
    end

    test "will not mark spammy Sponsors listing as approved when maintainer is suspended" do
      spammy_listing = create(:sponsors_listing, :spammy)
      sponsorable = spammy_listing.sponsorable
      sponsorable.mark_not_spammy
      sponsorable.suspend("Suspended!")
      refute_predicate sponsorable, :spammy?
      assert_predicate sponsorable, :suspended?

      RelistNonSpammySponsorsListingJob.perform_now(sponsorable: sponsorable)

      refute_predicate spammy_listing.reload, :approved?
    end

    test "will not mark non-spammy Sponsors listing as approved" do
      disabled_listing = create(:sponsors_listing, :disabled)
      sponsorable = disabled_listing.sponsorable
      refute_predicate sponsorable, :spammy?

      RelistNonSpammySponsorsListingJob.perform_now(sponsorable: sponsorable)

      refute_predicate disabled_listing.reload, :approved?
    end

    test "retries the job on dirty exit" do
      assert_retry_on_dirty_exit(job: RelistNonSpammySponsorsListingJob, args: [@non_spammer])
    end

    test "no-op when Sponsors listing is already approved" do
      approved_listing = create(:sponsors_listing, :approved)
      RelistNonSpammySponsorsListingJob.perform_now(sponsorable: approved_listing.sponsorable)
      assert_predicate approved_listing.reload, :approved?
    end
  else
    test "no-op when Sponsors is disabled" do
      RelistNonSpammySponsorsListingJob.perform_now(sponsorable: @non_spammer)
      assert_predicate @sponsors_listing.reload, :spammy?
    end
  end
end
