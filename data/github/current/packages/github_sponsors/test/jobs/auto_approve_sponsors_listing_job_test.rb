# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class AutoApproveSponsorsListingJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include JobTestHelper

  fixtures do
    @sponsorable = create(:user, :sponsors_auto_approvable)
    @listing = @sponsorable.sponsors_listing
    @listing.update!(state: :queued_for_auto_approval)
  end

  setup do
    disable_feature_flag(:live_sdn_screening)
  end

  if GitHub.sponsors_enabled?
    context "#perform" do
      test "approves an auto-approvable listing in pending_approval state" do
        pending_listing = @listing
        pending_listing.update!(state: :pending_approval)
        assert_predicate pending_listing, :auto_approvable?
        assert_predicate pending_listing, :pending_approval?

        AutoApproveSponsorsListingJob.perform_now(pending_listing)

        assert_predicate pending_listing.reload, :approved?
      end

      test "approves an auto-approvable listing in queued_for_auto_approval state" do
        assert_predicate @listing, :auto_approvable?
        assert_predicate @listing, :queued_for_auto_approval?

        AutoApproveSponsorsListingJob.perform_now(@listing)

        assert_predicate @listing.reload, :approved?
      end

      test "approves an auto approvable listing with SDN screening enabled" do
        enable_feature_flag(:live_sdn_screening)

        assert_predicate @listing, :auto_approvable?
        assert_predicate @listing, :queued_for_auto_approval?

        AutoApproveSponsorsListingJob.perform_now(@listing)

        assert_predicate @listing.reload, :approved?
      end

      test "does not approve an otherwise auto-approvable listing with SDN screening enabled and a blocking screening status" do
        @listing.sponsorable.trade_screening_record.hit_in_review!
        assert_predicate @listing.reload, :auto_approvable?
        assert_predicate @listing, :queued_for_auto_approval?

        enable_feature_flag(:live_sdn_screening)

        refute_predicate @listing.reload, :auto_approvable?

        AutoApproveSponsorsListingJob.perform_now(@listing)

        refute_predicate @listing.reload, :approved?
      end

      test "does nothing for an already approved listing" do
        assert @listing.approve!
        assert_predicate @listing, :auto_approvable?
        assert_predicate @listing, :approved?

        AutoApproveSponsorsListingJob.perform_now(@listing)

        assert_predicate @listing.reload, :approved?
      end

      test "does nothing for an already approved listing with SDN Screening enabled" do
        enable_feature_flag(:live_sdn_screening)

        assert @listing.approve!
        assert_predicate @listing, :auto_approvable?
        assert_predicate @listing, :approved?

        AutoApproveSponsorsListingJob.perform_now(@listing)

        assert_predicate @listing.reload, :approved?
      end

      test "reverts an ineligibile listing to pending approval" do
        @listing.active_stripe_connect_account.destroy!
        refute_predicate @listing.reload, :auto_approvable?
        assert_predicate @listing, :queued_for_auto_approval?

        AutoApproveSponsorsListingJob.perform_now(@listing)

        assert_predicate @listing.reload, :pending_approval?
      end

      test "instruments success metric" do
        assert_predicate @listing, :auto_approvable?
        assert_predicate @listing, :queued_for_auto_approval?

        AutoApproveSponsorsListingJob.perform_now(@listing)

        assert_dogstats_increment(1, "sponsors_listing.auto_approval", tags: ["success:true"])
      end

      test "instruments failure metric" do
        @listing.active_stripe_connect_account.destroy!
        refute_predicate @listing.reload, :auto_approvable?
        assert_predicate @listing, :queued_for_auto_approval?

        AutoApproveSponsorsListingJob.perform_now(@listing)

        assert_dogstats_increment(1, "sponsors_listing.auto_approval", tags: ["success:false"])
      end
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: AutoApproveSponsorsListingJob, args: [@listing]
    end
  else
    test "does nothing if sponsors disabled" do
      assert_predicate @listing, :auto_approvable?
      assert_predicate @listing, :queued_for_auto_approval?

      AutoApproveSponsorsListingJob.perform_now(@listing)

      assert_predicate @listing.reload, :queued_for_auto_approval?
    end
  end
end
