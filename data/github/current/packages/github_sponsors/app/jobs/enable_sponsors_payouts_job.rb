# typed: true
# frozen_string_literal: true

class EnableSponsorsPayoutsJob < ApplicationJob
  extend T::Sig

  queue_as :billing

  retry_on_dirty_exit

  sig { void }
  def perform
    payouts_enabled = 0

    listings.each do |listing|
      next unless meets_payout_requirements?(listing)

      SponsorsListing.throttle_writes_with_retry do
        listing.update!(payout_probation_ended_at: Time.zone.now)
      end

      listing.enable_payouts_for_active_stripe_connect_account

      payouts_enabled += 1
    end

    GitHub.dogstats.count("sponsors.payout_probation_ended", payouts_enabled)
  end

  private

  sig { returns T::Array[SponsorsListing] }
  def listings
    @listings ||= SponsorsListing
      .on_payout_probation
      .with_approved_state
      .without_current_pending_or_flagged_fraud_review
      .where("payout_probation_started_at < ?", SponsorsListing::PAYOUT_PROBATION_DAYS.days.ago)
      .to_a
  end

  sig { params(listing: SponsorsListing).returns(T.nilable(T::Boolean)) }
  def meets_payout_requirements?(listing)
    listing.uses_fiscal_host? || listing.stripe_w8_or_w9_verified?
  end
end
