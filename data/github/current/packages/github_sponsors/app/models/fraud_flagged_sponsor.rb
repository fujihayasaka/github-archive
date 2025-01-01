# typed: true
# frozen_string_literal: true

class FraudFlaggedSponsor < ApplicationRecord::Domain::Sponsors
  belongs_to :sponsors_fraud_review, required: true
  belongs_to :sponsor, class_name: "User", required: false

  validates :sponsor_id, presence: true
  validates :sponsor_id, uniqueness: { scope: :sponsors_fraud_review_id }
  validates :matched_current_ip, :matched_historical_ip, length: { maximum: 40 }
  validate :ensure_one_matched_field

  after_commit :instrument_flagged_sponsor

  private

  def ensure_one_matched_field
    if [
      matched_current_client_id,
      matched_current_ip,
      matched_historical_ip,
      matched_historical_client_id,
      matched_current_ip_region_and_user_agent,
    ].all?(&:blank?)
      errors.add :base, "Must have at least one matched field"
    end
  end

  def instrument_flagged_sponsor
    return unless sponsors_fraud_review&.sponsors_listing
    listing = T.must(T.must(sponsors_fraud_review).sponsors_listing)

    GlobalInstrumenter.instrument("sponsors.sponsor_fraud_flagged", {
      fraud_review: sponsors_fraud_review,
      listing: listing,
      sponsorable: listing.sponsorable,
      sponsor: sponsor,
      matched_current_client_id: matched_current_client_id,
      matched_current_ip: matched_current_ip,
      matched_historical_ip: matched_historical_ip,
      matched_historical_client_id: matched_historical_client_id,
      matched_current_ip_region_and_user_agent: matched_current_ip_region_and_user_agent,
    })
  end
end
