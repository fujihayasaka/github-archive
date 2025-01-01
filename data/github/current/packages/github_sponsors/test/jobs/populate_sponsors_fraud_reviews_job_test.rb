# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require_relative "../../../../packages/github_sponsors/app/models/sponsors/k_v"

class PopulateSponsorsFraudReviewsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account, tier_count: 0,
      last_payout_at: 1.day.ago.beginning_of_day)
    @pricey_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing,
      monthly_price_in_cents: 500_00)
    @cheap_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing,
      monthly_price_in_cents: 500_00 / 2)
    @sponsorable = @sponsors_listing.sponsorable
    @stripe_account = @sponsors_listing.active_stripe_connect_account
  end

  test "creates a fraud review for listing whose current balance exceeds $5,000" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricey_tier)
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

  test "does not create a fraud review for listing whose current balance exceeds $5,000 with invoiced sponsorship" do
    invoiced_sponsor = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
    ship = create(:sponsorship, :invoiced, sponsorable: @sponsorable, sponsor: invoiced_sponsor,
      tier: @pricey_tier, sponsors_listing: @sponsors_listing)

    travel_to(@sponsors_listing.last_payout_at + 1.day) do
      create_list(:payouts_ledger_entry, 2, :transfer, stripe_connect_account: @stripe_account,
        amount_in_subunits: 2500_00)
    end

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "does not create a fraud review for listing whose current balance exceeds $5,000 with trusted sponsorship" do
    trusted_sponsorable = create(:user, created_at: 2.years.ago)
    trusted_listing = create(:sponsors_listing, :approved, sponsorable: trusted_sponsorable, created_at: 2.years.ago,
      last_payout_at: 1.day.ago.beginning_of_day)

    sponsorship_from_trusted = create(:sponsorship, sponsor: trusted_sponsorable, sponsorable: @sponsorable, tier: @pricey_tier)
    travel_to(T.must(@sponsors_listing.last_payout_at) + 1.day) do
      create_list(:payouts_ledger_entry, 2, :transfer, stripe_connect_account: @stripe_account,
        amount_in_subunits: 2500_00)
    end
    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "does not create a fraud review for listing whose current balance is less than $5,000" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @cheap_tier)
    travel_to(@sponsors_listing.last_payout_at + 1.day) do
      create_list(:payouts_ledger_entry, 2, :transfer, stripe_connect_account: @stripe_account,
        amount_in_subunits: 250_00)
    end
    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "creates a fraud review for listing with two new sponsors" do
    # "old_user" creates a user with a created at date of 10 days ago
    new_sponsor1 = create(:old_user)
    new_sponsor2 = create(:old_user)
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricey_tier, sponsor: new_sponsor1)
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricey_tier, sponsor: new_sponsor2)

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

  test "creates a single open fraud review when user has multiple resolved reviews prior to last payout" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricey_tier)
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
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricey_tier)

    assert_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
    assert_equal @sponsors_listing, T.must(SponsorsFraudReview.last).sponsors_listing
  end

  test "creates a fraud review for listing with upgrade sponsorship amount totalling a fraudulent amount since the last payout" do
    old_sponsorship = travel_to(@sponsors_listing.last_payout_at - 1.day) do
      create(:sponsorship, sponsorable: @sponsorable, tier: @cheap_tier)
    end
    old_sponsorship.subscribable_selected_at = Time.now
    old_sponsorship.tier = @pricey_tier
    old_sponsorship.save!

    assert_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
    assert_equal @sponsors_listing, T.must(SponsorsFraudReview.last).sponsors_listing
  end

  test "creates fraud review when a maintainer has a lot of sponsorship churn and goes over the fraudulent amount" do
    # $500 tier:
    pricier_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing,
      monthly_price_in_cents: 500_00 + 100_00)

    # Create some old sponsorships totalling $1,000:
    old_sponsorships = travel_to(@sponsors_listing.last_payout_at - 1.day) do
      create_list(:sponsorship, 2, sponsorable: @sponsorable, tier: pricier_tier)
    end
    assert old_sponsorships.sum(0) { |sponsorship| sponsorship.amount }.cents > 500_00

    # One person cancels their $500 sponsorship:
    old_sponsorships.first.update!(active: false)

    # Someone new starts sponsoring at $500:
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricey_tier)

    assert_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
    assert_equal @sponsors_listing, T.must(SponsorsFraudReview.last).sponsors_listing
  end

  test "does not create fraud review for listing with sponsorship amount exceeding threshold if those sponsorships were made before the last payout" do
    travel_to(@sponsors_listing.last_payout_at - 1.day) do
      create(:sponsorship, sponsorable: @sponsorable, tier: @pricey_tier)
    end

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "only considers active sponsorships" do
    create(:sponsorship, :inactive, sponsorable: @sponsorable, tier: @pricy_tier)

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "does not create a fraud review for listing with sponsorship amount exceeding threshold if those sponsorships include invoiced payments" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @cheap_tier)
    create(:sponsorship, :invoiced, sponsorable: @sponsorable, tier: @invoiced_tier)

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "does not create a fraud review for listing that has not reached threshold since last payout" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @cheap_tier)

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "does not create a fraud review for eligible listing if review already created after last payout date" do
    create(:sponsors_fraud_review, sponsors_listing: @sponsors_listing)
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricey_tier)

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "does not create review for listings that have a review created on same day job was run" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricey_tier)
    travel_to(@sponsors_listing.last_payout_at + 1.hour) do
      create(:sponsors_fraud_review, sponsors_listing: @sponsors_listing)
    end

    assert_no_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
    end
  end

  test "creates a fraud review if last review was before last payout date" do
    create(:sponsorship, sponsorable: @sponsorable, tier: @pricey_tier)
    travel_to(@sponsors_listing.last_payout_at - 1.day) do
      create(:sponsors_fraud_review, sponsors_listing: @sponsors_listing)
    end

    assert_difference(-> { SponsorsFraudReview.count }) do
      PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
        PopulateSponsorsFraudReviewsJob.perform_now
      end
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
        PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
          PopulateSponsorsFraudReviewsJob.perform_now
        end
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
        PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
          PopulateSponsorsFraudReviewsJob.perform_now
        end
      end
    end
  end

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
    assert_nil Sponsors::KV.store.get("populate_sponsors_fraud_reviews_payout_entry.maint.id").value!

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

    assert_equal last_sponsors_listing.ledger_entries.last.id, Sponsors::KV.store.get("populate_sponsors_fraud_reviews_payout_entry.maint.id").value!.to_i
  end

  test "does not change cached id for Billing::PayoutsLedgerEntry net transfer when there are no new ledger entries" do
    assert_nil Sponsors::KV.store.get("populate_sponsors_fraud_reviews_payout_entry.maint.id").value!

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

    assert_equal last_sponsors_listing.ledger_entries.last.id, Sponsors::KV.store.get("populate_sponsors_fraud_reviews_payout_entry.maint.id").value!.to_i

    PopulateSponsorsFraudReviewsJob.stub_const(:STARTING_ID, 1) do
      PopulateSponsorsFraudReviewsJob.perform_now
    end

    assert_equal last_sponsors_listing.ledger_entries.last.id, Sponsors::KV.store.get("populate_sponsors_fraud_reviews_payout_entry.maint.id").value!.to_i
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: PopulateSponsorsFraudReviewsJob
  end


  test "locks job to avoid multiple running concurrently" do
    assert_enqueued_jobs(1) do
      PopulateSponsorsFraudReviewsJob.perform_later
      PopulateSponsorsFraudReviewsJob.perform_later
      PopulateSponsorsFraudReviewsJob.perform_later
    end
  end
end if GitHub.sponsors_enabled?
