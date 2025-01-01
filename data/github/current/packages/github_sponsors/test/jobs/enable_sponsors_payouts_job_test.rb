# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class EnableSponsorsPayoutsJobTest < GitHub::TestCase
  include JobTestHelper

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  test "does not end payout probation unless stripe tax documents completed" do
    SponsorsListing.stub_const(:PAYOUT_PROBATION_DAYS, 3) do
      listing = create :sponsors_listing, \
        :approved,
        :with_w8_or_w9_requested_but_unverified_stripe_account,
        payout_probation_started_at: 4.days.ago

      EnableSponsorsPayoutsJob.perform_now

      assert_predicate listing.reload, :on_payout_probation?
    end
  end

  test "does not end payout probation if pending or flagged fraud reviews exist" do
    no_fraud_reviews_listing, resolved_listing, pending_listing, flagged_listing = create_list(
      :sponsors_listing, 4, :approved, :with_w8_or_w9_verified_stripe_account, payout_probation_started_at: 4.days.ago
    )
    create(:sponsors_fraud_review, sponsors_listing: pending_listing)
    create(:sponsors_fraud_review, :resolved, sponsors_listing: resolved_listing)
    create(:sponsors_fraud_review, :flagged, sponsors_listing: flagged_listing)

    SponsorsListing.stub_const(:PAYOUT_PROBATION_DAYS, 3) do
      EnableSponsorsPayoutsJob.perform_now
    end

    refute_predicate no_fraud_reviews_listing.reload, :on_payout_probation?
    refute_predicate resolved_listing.reload, :on_payout_probation?
    assert_predicate pending_listing.reload, :on_payout_probation?
    assert_predicate flagged_listing.reload, :on_payout_probation?
  end

  test "ends payout probation for listings with completed stripe tax documents" do
    SponsorsListing.stub_const(:PAYOUT_PROBATION_DAYS, 3) do
      listing_with_completed_stripe_tax_documents = create :sponsors_listing, \
        :approved,
        :with_w8_or_w9_requested_but_unverified_stripe_account,
        payout_probation_started_at: 4.days.ago

      listing_with_completed_stripe_tax_documents.stripe_connect_accounts.first.update!(
        w8_or_w9_verified: true,
      )

      EnableSponsorsPayoutsJob.perform_now

      refute_predicate listing_with_completed_stripe_tax_documents.reload, :on_payout_probation?
    end
  end

  test "ends payout probation for eligible org listings" do
    SponsorsListing.stub_const(:PAYOUT_PROBATION_DAYS, 3) do
      listing = create :sponsors_listing, :approved, :for_org, :with_w8_or_w9_verified_stripe_account,
        payout_probation_started_at: 4.days.ago

      EnableSponsorsPayoutsJob.perform_now
      refute_predicate listing.reload, :on_payout_probation?
    end
  end

  test "ends payout probation for eligible orgs using a fiscal host" do
    SponsorsListing.stub_const(:PAYOUT_PROBATION_DAYS, 3) do
      listing = create :sponsors_listing, :approved, :for_org, :with_fiscal_host,
        payout_probation_started_at: 4.days.ago

      EnableSponsorsPayoutsJob.perform_now
      refute_predicate listing.reload, :on_payout_probation?
    end
  end

  test "does not enqueue ConfigureStripeAccount job for non-Stripe listing" do
    SponsorsListing.stub_const(:PAYOUT_PROBATION_DAYS, 3) do
      listing = create :sponsors_listing, :approved, :with_fiscal_host,
        payout_probation_started_at: 4.days.ago

      EnableSponsorsPayoutsJob.perform_now

      assert_enqueued_jobs 0, only: ConfigureStripeAccountJob
      assert listing.reload.payout_probation_ended_at
    end
  end

  test "enqueues ConfigureStripeAccount job for Stripe listing" do
    SponsorsListing.stub_const(:PAYOUT_PROBATION_DAYS, 3) do
      listing = create :sponsors_listing, :approved, :with_w8_or_w9_verified_stripe_account,
        payout_probation_started_at: 4.days.ago

      EnableSponsorsPayoutsJob.perform_now

      assert_enqueued_jobs 1, only: ConfigureStripeAccountJob, queue: :stripe
      assert listing.reload.payout_probation_ended_at
    end
  end

  test "reports count to dogstats" do
    GitHub.dogstats.expects(:increment).at_least_once
    GitHub.dogstats.expects(:count)
      .with("sponsors.payout_probation_ended", 1)
      .at_least_once

    SponsorsListing.stub_const(:PAYOUT_PROBATION_DAYS, 3) do
      eligible_listing = create :sponsors_listing, :approved, :with_w8_or_w9_verified_stripe_account,
        payout_probation_started_at: 4.days.ago

      # ineligible_listing
      create :sponsors_listing, :approved, payout_probation_started_at: 4.days.ago

      EnableSponsorsPayoutsJob.perform_now
    end
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: EnableSponsorsPayoutsJob
  end
end
