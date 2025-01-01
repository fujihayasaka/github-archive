# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class BanSponsorsListingJobTest < GitHub::TestCase
  include HydroTestHelpers
  include JobTestHelper

  fixtures do
    @staff = create(:staff_admin_user)
    @sponsors_listing = create(:sponsors_listing, :approved)
    @stafftools_metadata = @sponsors_listing.stafftools_metadata
    @ban_reason = "Questionable behavior"
  end

  if GitHub.sponsors_enabled?
    test "bans the specified Sponsors listing" do
      refute_predicate @sponsors_listing, :banned?

      BanSponsorsListingJob.perform_now(sponsors_listing: @sponsors_listing, actor: @staff, ban_reason: @ban_reason)

      assert_predicate @sponsors_listing.reload, :banned?
      assert_equal @ban_reason, @stafftools_metadata.reload.banned_reason
      assert_equal @staff, @stafftools_metadata.banned_by
    end

    test "retries the job on dirty exit" do
      assert_retry_on_dirty_exit(job: BanSponsorsListingJob, args: [{
        sponsors_listing: @sponsors_listing,
        actor: @staff,
        ban_reason: @ban_reason,
      }])
    end

    test "no-op when Sponsors listing is already banned" do
      old_banned_reason = "Old reason"
      old_banned_by = create(:user)
      banned_listing = create(:sponsors_listing, :banned, banned_by: old_banned_by, banned_reason: old_banned_reason)

      BanSponsorsListingJob.perform_now(sponsors_listing: banned_listing, actor: @staff, ban_reason: @ban_reason)

      assert_predicate banned_listing.reload, :banned?
      assert_equal old_banned_reason, banned_listing.reload_stafftools_metadata.banned_reason
      assert_equal old_banned_by, banned_listing.stafftools_metadata.banned_by
    end

    test "instruments a ban event" do
      events = subscribe("sponsors_memberships_ban.create")

      # serialize before transition since events will be emitted before state transition
      serialized_sponsorable = Hydro::EntitySerializer.user(@sponsors_listing.sponsorable)
      serialized_listing = Hydro::EntitySerializer.sponsors_listing(@sponsors_listing)
      serialized_stafftools_metadata = Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        @sponsors_listing.stafftools_metadata
      )

      assert_difference(-> { events.size }) do
        BanSponsorsListingJob.perform_now(sponsors_listing: @sponsors_listing, actor: @staff, ban_reason: @ban_reason)
      end

      expected_message = {
        user: serialized_sponsorable,
        action: "BANNED",
        listing: serialized_listing,
        listing_stafftools_metadata: serialized_stafftools_metadata,
        automated: false,
      }

      assert_hydro_published(expected_message, schema: "github.sponsors.v0.AccountStatusChange")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.AccountStatusChange")
    end
  else
    test "no-op when Sponsors is disabled" do
      BanSponsorsListingJob.perform_now(sponsors_listing: @sponsors_listing, actor: @staff, ban_reason: @ban_reason)

      refute_predicate @sponsors_listing.reload, :banned?
      assert_nil @stafftools_metadata.reload.banned_reason
      assert_nil @stafftools_metadata.banned_by
    end
  end
end
