# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SponsorsListingNoLongerSponsorableJobTest < GitHub::TestCase
  include HydroTestHelpers
  include JobTestHelper
  include GitHub::SponsorsInstrumentationTestHelpers

  fixtures do
    @staff = create(:staff_admin_user)
    @sponsors_listing = create(:sponsors_listing, :approved)
    @sponsorable = @sponsors_listing.sponsorable
    @active_sponsorship = create(:sponsorship, sponsorable: @sponsorable)
    @other_active_sponsorship = create(:sponsorship, sponsorable: @sponsorable)
    @inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: @sponsorable)
    @other_user_sponsorship = create(:sponsorship)
  end

  if GitHub.sponsors_enabled?
    test "immediately cancels active sponsorships for a listing" do
      assert_predicate @sponsors_listing, :has_active_subscription_items?
      assert_predicate @active_sponsorship, :active?
      assert_predicate @other_active_sponsorship, :active?
      refute_predicate @inactive_sponsorship, :active?
      assert_predicate @other_user_sponsorship, :active?

      SponsorsListingNoLongerSponsorableJob.perform_now(sponsors_listing: @sponsors_listing, actor: @staff)

      refute_predicate @sponsors_listing.reload, :has_active_subscription_items?
      refute_predicate @active_sponsorship.reload, :active?
      refute_predicate @other_active_sponsorship.reload, :active?
      refute_predicate @inactive_sponsorship.reload, :active?
      assert_predicate @other_user_sponsorship.reload, :active?
    end

    test "instruments Hydro event SponsorshipCancelRequest for each active sponsorship cancellation" do
      assert_predicate @active_sponsorship, :active?
      assert_predicate @other_active_sponsorship, :active?

      SponsorsListingNoLongerSponsorableJob.perform_now(
        sponsors_listing: @sponsors_listing,
        actor: @staff,
        reason: :BANNED_LISTING
      )

      refute_predicate @active_sponsorship.reload, :active?
      refute_predicate @other_active_sponsorship.reload, :active?

      assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_sponsorship_cancel_request_hydro_published(
        sponsorship: @active_sponsorship,
        reason: :BANNED_LISTING,
        actor: @staff,
      )
      assert_sponsorship_cancel_request_hydro_published(
        sponsorship: @other_active_sponsorship,
        reason: :BANNED_LISTING,
        actor: @staff,
      )
    end

    test "e-mails current sponsors that listing is no longer sponsorable" do
      @sponsors_listing.expects(:email_sponsors_no_longer_sponsorable).once
        .with([@active_sponsorship, @other_active_sponsorship])

      SponsorsListingNoLongerSponsorableJob.perform_now(sponsors_listing: @sponsors_listing, actor: @staff)
    end

    test "syncs sponsors search indices" do
      assert_enqueued_with(job: SyncSponsorsSearchIndicesJob, args: [{ sponsorable: @sponsorable }]) do
        SponsorsListingNoLongerSponsorableJob.perform_now(sponsors_listing: @sponsors_listing, actor: @staff)
      end
    end

    test "retries the job on dirty exit" do
      assert_retry_on_dirty_exit(job: SponsorsListingNoLongerSponsorableJob, args: [{
        sponsors_listing: @sponsors_listing,
        actor: @staff,
      }])
    end
  else
    test "no-op when Sponsors is disabled" do
      assert_predicate @sponsors_listing, :has_active_subscription_items?

      SponsorsListingNoLongerSponsorableJob.perform_now(sponsors_listing: @sponsors_listing, actor: @staff)

      assert_predicate @sponsors_listing.reload, :has_active_subscription_items?
    end
  end
end
