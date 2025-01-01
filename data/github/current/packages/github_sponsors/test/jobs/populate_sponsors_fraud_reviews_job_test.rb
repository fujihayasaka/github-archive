# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class PopulateSponsorsFraudReviewsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account, tier_count: 0,
      last_payout_at: 1.day.ago.beginning_of_day)
    @pricy_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing,
      monthly_price_in_cents: 400_00)
    @cheap_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing,
      monthly_price_in_cents: 400_00 / 2)
    @invoiced_tier = create(:sponsors_tier, :invoiced, sponsors_listing: @sponsors_listing,
      monthly_price_in_cents: 500_00)
    @sponsorable = @sponsors_listing.sponsorable
    @stripe_account = @sponsors_listing.active_stripe_connect_account
  end

  test "creates a fraud review for listing whose current balance exceeds $5,000" do
    travel_to(@sponsors_listing.last_payout_at + 1.day) do
      create_list(:payouts_ledger_entry, 2, :transfer, stripe_connect_account: @stripe_account,
        amount_in_subunits: 2500_00)
    end

    assert_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
    assert_equal @sponsors_listing, T.must(SponsorsFraudReview.last).sponsors_listing
  end

  # See https://github.com/github/sponsors/issues/3650
  test "creates a single open fraud review when user has multiple resolved reviews prior to last payout" do
    travel_to(@sponsors_listing.last_payout_at - 1.day) do
      create_list(:sponsors_fraud_review, 2, :resolved, sponsors_listing: @sponsors_listing)
    end
    travel_to(@sponsors_listing.last_payout_at + 1.day) do
      create_list(:payouts_ledger_entry, 2, :transfer, stripe_connect_account: @stripe_account,
        amount_in_subunits: 2500_00)
    end

    assert_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
    assert_equal @sponsors_listing, T.must(SponsorsFraudReview.last).sponsors_listing
  end

  test "creates a fraud review for listing with new sponsorship amount totalling a fraudulent amount since the last payout" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricy_tier)

    assert_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end
    assert_equal @sponsors_listing, T.must(SponsorsFraudReview.last).sponsors_listing
  end

  test "creates a fraud review for listing with upgrade sponsorship amount totalling a fraudulent amount since the last payout" do
    old_sponsorship = travel_to(@sponsors_listing.last_payout_at - 1.day) do
      create(:sponsorship, sponsorable: @sponsorable, tier: @cheap_tier)
    end
    old_sponsorship.subscribable_selected_at = Time.now
    old_sponsorship.tier = @pricy_tier
    old_sponsorship.save!

    assert_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end
    assert_equal @sponsors_listing, T.must(SponsorsFraudReview.last).sponsors_listing
  end

  # https://github.com/github/sponsors/issues/2370
  test "creates fraud review when a maintainer has a lot of sponsorship churn and goes over the fraudulent amount" do
    # $500 tier:
    pricier_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing,
      monthly_price_in_cents: 400_00 + 100_00)

    # Create some old sponsorships totalling $1,000:
    old_sponsorships = travel_to(@sponsors_listing.last_payout_at - 1.day) do
      create_list(:sponsorship, 2, sponsorable: @sponsorable, tier: pricier_tier)
    end
    assert old_sponsorships.sum(0) { |sponsorship| sponsorship.amount }.cents > 400_00

    # One person cancels their $500 sponsorship:
    old_sponsorships.first.update!(active: false)

    # Someone new starts sponsoring at $400:
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricy_tier)

    assert_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end
    assert_equal @sponsors_listing, T.must(SponsorsFraudReview.last).sponsors_listing
  end

  # https://github.com/github/sponsors/issues/2370
  test "does not create fraud review for listing with sponsorship amount exceeding threshold if those sponsorships were made before the last payout" do
    travel_to(@sponsors_listing.last_payout_at - 1.day) do
      create(:sponsorship, sponsorable: @sponsorable, tier: @pricy_tier)
    end

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end
  end

  test "only considers active sponsorships" do
    create(:sponsorship, :inactive, sponsorable: @sponsorable, tier: @pricy_tier)

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end
  end

  # https://github.com/github/sponsors/issues/2680
  test "does not create a fraud review for listing with sponsorship amount exceeding threshold if those sponsorships include invoiced payments" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @cheap_tier)
    create(:sponsorship, :invoiced, sponsorable: @sponsorable, tier: @invoiced_tier)

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end
  end

  test "does not create a fraud review for listing that has not reached threshold since last payout" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @cheap_tier)

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end
  end

  test "does not create a fraud review for eligible listing if review already created after last payout date" do
    create(:sponsors_fraud_review, sponsors_listing: @sponsors_listing)
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricy_tier)

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end
  end

  test "does not create review for listings that have a review created on same day job was run" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricy_tier)
    travel_to(@sponsors_listing.last_payout_at + 1.hour) do
      create(:sponsors_fraud_review, sponsors_listing: @sponsors_listing)
    end

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end
  end

  test "creates a fraud review if last review was before last payout date" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricy_tier)
    travel_to(@sponsors_listing.last_payout_at - 1.day) do
      create(:sponsors_fraud_review, sponsors_listing: @sponsors_listing)
    end

    assert_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end
    assert_equal @sponsors_listing, T.must(SponsorsFraudReview.last).sponsors_listing
  end

  test "does not create a fraud review for listing with less than a fraudulent amount even if listing has never been paid out" do
    travel_to("2020-04-08") do
      create(:payouts_ledger_entry, :transfer,
        stripe_connect_account: @stripe_account,
        transaction_timestamp: 1.week.ago,
        amount_in_subunits: 4999_00,
      )
      @sponsors_listing.update!(last_payout_at: nil)
      create(:sponsorship, sponsorable: @sponsorable, tier: @cheap_tier)

      assert_no_difference(-> { SponsorsFraudReview.count }) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "does not create a fraud review for listing with no sponsorships and no transfers" do
    travel_to("2020-04-08") do
      create(:payouts_ledger_entry, :github_match,
        stripe_connect_account: @stripe_account,
        transaction_timestamp: 1.week.ago,
        amount_in_subunits: 5000_00,
      )

      assert_no_difference(-> { SponsorsFraudReview.count }) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  # https://github.com/github/sponsors/issues/2492
  test "does not create fraud reviews since there is a pending review already created" do
    # Fraud Review resolved before the last payout at
    travel_to(@sponsors_listing.last_payout_at - 2.days) do
      create(:sponsors_fraud_review, :resolved, sponsors_listing: @sponsors_listing)
    end

    travel_to(@sponsors_listing.last_payout_at + 2.days) do
      create_list(:payouts_ledger_entry, 2, :transfer, stripe_connect_account: @stripe_account,
        amount_in_subunits: 2500_00)
    end

    # Create pending fraud review
    travel_to(@sponsors_listing.last_payout_at + 3.days) do
      create(:sponsors_fraud_review, sponsors_listing: @sponsors_listing)
    end

    # Should not create a new review since there is a pending review already created
    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "caches last processed id for Billing::PayoutsLedgerEntry net transfer" do
    assert_nil GitHub.kv.get("populate_sponsors_fraud_reviews_payout_entry.maint.id").value!

    sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account, tier_count: 0,
      last_payout_at: @sponsors_listing.last_payout_at)
    last_sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account, tier_count: 0,
      last_payout_at: @sponsors_listing.last_payout_at)

    travel_to(@sponsors_listing.last_payout_at + 1.day) do
      create_list(:payouts_ledger_entry, 2, :transfer, stripe_connect_account: sponsors_listing.active_stripe_connect_account, amount_in_subunits: 2500_00)
      create_list(:payouts_ledger_entry, 2, :transfer, stripe_connect_account: last_sponsors_listing.active_stripe_connect_account, amount_in_subunits: 2500_00)
    end

    PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end

    assert_equal last_sponsors_listing.ledger_entries.last.id, GitHub.kv.get("populate_sponsors_fraud_reviews_payout_entry.maint.id").value!.to_i
  end

  test "does not change cached id for Billing::PayoutsLedgerEntry net transfer when there are no new ledger entries" do
    assert_nil GitHub.kv.get("populate_sponsors_fraud_reviews_payout_entry.maint.id").value!

    sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account, tier_count: 0,
      last_payout_at: @sponsors_listing.last_payout_at)
    last_sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account, tier_count: 0,
      last_payout_at: @sponsors_listing.last_payout_at)

    travel_to(@sponsors_listing.last_payout_at + 1.day) do
      create_list(:payouts_ledger_entry, 2, :transfer, stripe_connect_account: sponsors_listing.active_stripe_connect_account, amount_in_subunits: 2500_00)
      create_list(:payouts_ledger_entry, 2, :transfer, stripe_connect_account: last_sponsors_listing.active_stripe_connect_account, amount_in_subunits: 2500_00)
    end

    PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end

    assert_equal last_sponsors_listing.ledger_entries.last.id, GitHub.kv.get("populate_sponsors_fraud_reviews_payout_entry.maint.id").value!.to_i

    PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end

    assert_equal last_sponsors_listing.ledger_entries.last.id, GitHub.kv.get("populate_sponsors_fraud_reviews_payout_entry.maint.id").value!.to_i
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: PopulateSponsorsFraudReviewsJob
  end

  # https://github.com/github/sponsors/issues/3565
  # https://github.com/github/sponsors/issues/3454
  test "locks job to avoid multiple running concurrently" do
    assert_enqueued_jobs(1) do
      PopulateSponsorsFraudReviewsJob.perform_later
      PopulateSponsorsFraudReviewsJob.perform_later
      PopulateSponsorsFraudReviewsJob.perform_later
    end
  end
end if GitHub.sponsors_enabled?
