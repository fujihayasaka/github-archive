# typed: true
# frozen_string_literal: true

require_relative "../models/sponsors/k_v"

class PopulateSponsorsFraudReviewsJob < ApplicationJob
  queue_as :sponsors_application_processing

  retry_on_dirty_exit

  BATCH_SIZE = 500
  TRANSACTION_LIMIT = 500_00

  # Last Billing::PayoutsLedgerEntry ID before this job started timing out on
  #   Oct 4, 2021
  STARTING_ID = 1186788

  LAST_ID_KEY = "populate_sponsors_fraud_reviews_payout_entry.maint.id"
  LOCK_KEY = "populate-sponsors-fraud-reviews-job"

  # Ensure that this job is not run concurrently.
  locked_by timeout: 1.hour, key: ->(_job) { LOCK_KEY }

  def perform
    Failbot.push(app: "github-sponsors")

    flaggable_listing_ids.each do |listing_id|
      SponsorsFraudReview.throttle_writes_with_retry do
        SponsorsFraudReview.create!(sponsors_listing_id: listing_id)
      end
    end
    ApplicationRecord::Mysql5.throttle_writes_with_retry do
      Sponsors::KV.store.set(LAST_ID_KEY, last_processed_payouts_ledger_entry_id)
    end
  end

  private

  def candidate_listing_ids
    candidate_listing_ids = Set.new(candidate_new_and_upgrade_listing_ids) | Set.new(candidate_transfer_volume_listing_ids)
    filter_listing_ids_with_invoiced_or_trusted_sponsor(candidate_listing_ids)
    filter_listing_ids_with_two_new_sponsors(candidate_listing_ids)
  end

  def filter_listing_ids_with_invoiced_or_trusted_sponsor(candidate_listing_ids)
    candidate_listing_ids.each do |candidate_listing_id|
      listing = SponsorsListing.find_by(id: candidate_listing_id)
      sponsorships = Sponsorship.where(sponsorable_id: T.must(listing).sponsorable_id)
      sponsorships.each do |sponsorship|
        sponsor = User.find_by(id: sponsorship.sponsor_id)
        #  if the sponsor is invoiced
        if T.must(sponsor).sponsors_invoiced?
          candidate_listing_ids.delete(T.must(listing).id)
        end

        funder_listing = SponsorsListing.find_by(sponsorable_id: T.must(sponsor).id)
        # if the sponsor/funder here has a sponsors listing, and that sponsors listing is older than one year
        if funder_listing && T.must(T.must(funder_listing).created_at) < 1.year.ago
          candidate_listing_ids.delete(T.must(listing).id)
        end
      end
    end
  end

  def filter_listing_ids_with_two_new_sponsors(candidate_listing_ids)
    candidate_listing_ids.each do |candidate_listing_id|
      new_sponsors_count = 0
      listing = SponsorsListing.find_by(id: candidate_listing_id)
      sponsorships = Sponsorship.where(sponsorable_id: T.must(listing).sponsorable_id)
      sponsorships.each do |sponsorship|
        sponsor = User.find_by(id: sponsorship.sponsor_id)
        if T.must(T.must(sponsor).created_at) > 180.days.ago
          new_sponsors_count += 1
        end
      end
      if sponsorships.count > 1 && new_sponsors_count < 2
        candidate_listing_ids.delete(T.must(listing).id)
      end
    end
  end

  # Private: Find listings whose new sponsorships and upgraded sponsorships since their last
  # payout totals at least $500.
  def candidate_new_and_upgrade_listing_ids
    SponsorsListing
      .with_min_sponsorship_amount_since_last_payout(TRANSACTION_LIMIT)
      .pluck(:id)
  end

  # Private: Find listings whose current balance exceeds $5,000
  def candidate_transfer_volume_listing_ids
    Billing::PayoutsLedgerEntry
      .where(id: candidate_payouts_ledger_entry_ids)
      .group("sponsors_listing_id")
      .having("SUM(amount_in_subunits) >= ?", 5000_00)
      .pluck("sponsors_listing_id")
  end

  # Private: Last Billing::PayoutsLedgerEntry id cached by previous job run.
  def last_cached_payouts_ledger_entry_id
    return @last_cached_payouts_ledger_entry_id if defined?(@last_cached_payouts_ledger_entry_id)

    cached_payouts_ledger_entry_id = Sponsors::KV.store.get(LAST_ID_KEY).value!

    @last_cached_payouts_ledger_entry_id = if cached_payouts_ledger_entry_id.present?
      cached_payouts_ledger_entry_id.to_i
    else
      STARTING_ID
    end
  end

  # Private: Last Billing::PayoutsLedgerEntry id processed on this run.
  def last_processed_payouts_ledger_entry_id
    last_candidate_payouts_ledger_entry_id = candidate_payouts_ledger_entry_ids_in_batch.last

    if last_candidate_payouts_ledger_entry_id.present?
      last_candidate_payouts_ledger_entry_id.to_s
    elsif last_cached_payouts_ledger_entry_id.present?
      last_cached_payouts_ledger_entry_id.to_s
    else
      STARTING_ID.to_s
    end
  end

  # Private: Find batch of Billing::PayoutsLedgerEntry to process.
  def candidate_payouts_ledger_entry_ids_in_batch
    return @candidate_payouts_ledger_entry_ids_in_batch if defined?(@candidate_payouts_ledger_entry_ids_in_batch)

    @candidate_payouts_ledger_entry_ids_in_batch = Billing::PayoutsLedgerEntry
      .where("id > ?", last_cached_payouts_ledger_entry_id)
      .order(:id)
      .limit(BATCH_SIZE)
      .pluck(:id)
  end

  # Private: Find transfers and reversals after a listing's last payout.
  def candidate_payouts_ledger_entry_ids
    Billing::PayoutsLedgerEntry
      .where(id: candidate_payouts_ledger_entry_ids_in_batch)
      .order(:id)
      .net_transfers
      .since_last_sponsors_payout
      .pluck(:id)
  end

  def flaggable_listing_ids
    SponsorsListing.without_fraud_review_since_last_payout
      .where(id: candidate_listing_ids)
      .pluck(:id)
  end
end
