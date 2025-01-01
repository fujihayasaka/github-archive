# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class AutoAcceptSponsorsApplicationsJobTest < GitHub::TestCase
  include JobTestHelper

  if GitHub.sponsors_enabled?
    fixtures do
      sponsorable = create(:user, :sponsors_old_enough_to_not_get_auto_banned)
      @listing = create(:sponsors_listing, :waitlisted,
        sponsorable: sponsorable,
        billing_country: SponsorsListing.auto_acceptable_countries.sample,
        country_of_residence: SponsorsListing.auto_acceptable_countries.sample,
      )
      @unacceptable_billing_listing = create(:sponsors_listing, :waitlisted, billing_country: "AF")
      @unacceptable_residence_listing = create(:sponsors_listing, :waitlisted,
        country_of_residence: "AF")
      @ignored_listing = create(:sponsors_listing, :waitlisted, :ignored,
        billing_country: SponsorsListing.auto_acceptable_countries.sample,
        country_of_residence: SponsorsListing.auto_acceptable_countries.sample,)
    end

    test "auto-accepts non-ignored listing that is eligible for auto acceptance" do
      assert_predicate @listing, :waitlisted?
      assert_predicate @listing, :auto_acceptable?
      assert_predicate @listing, :eligible_for_sponsors?

      AutoAcceptSponsorsApplicationsJob.perform_now

      assert_predicate @listing.reload, :draft?
    end

    test "does not accept ignored listing that is otherwise eligible for auto acceptance" do
      assert_predicate @ignored_listing, :waitlisted?
      AutoAcceptSponsorsApplicationsJob.perform_now
      refute_predicate @ignored_listing.reload, :draft?
    end

    test "does not accept listing with billing that is not in an auto-acceptable country" do
      assert_predicate @unacceptable_billing_listing, :waitlisted?
      refute_predicate @unacceptable_billing_listing, :auto_acceptable?

      AutoAcceptSponsorsApplicationsJob.perform_now

      refute_predicate @unacceptable_billing_listing.reload, :draft?
    end

    test "does not accept listing with residence that is not in an auto-acceptable country" do
      assert_predicate @unacceptable_residence_listing, :waitlisted?
      refute_predicate @unacceptable_residence_listing, :auto_acceptable?

      AutoAcceptSponsorsApplicationsJob.perform_now

      refute_predicate @unacceptable_residence_listing.reload, :draft?
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: AutoAcceptSponsorsApplicationsJob
    end
  end
end
