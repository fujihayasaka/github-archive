# typed: true
# frozen_string_literal: true

class SponsorshipNewsletterTier < ApplicationRecord::Domain::Sponsors
  belongs_to :sponsorship_newsletter, required: true
  belongs_to :sponsors_tier, required: true

  validates :sponsors_tier_id, uniqueness: { scope: :sponsorship_newsletter_id }
  validate :tier_must_belong_to_sponsors_listing
  validate :tier_must_not_be_draft

  private

  def tier_must_belong_to_sponsors_listing
    return unless sponsorship_newsletter

    sponsors_listing = T.must(sponsorship_newsletter).sponsors_listing
    return unless sponsors_listing
    return if sponsors_listing.id == sponsors_tier&.sponsors_listing_id

    errors.add(:sponsors_tier, "must be for this sponsorable's sponsors listing")
  end

  def tier_must_not_be_draft
    if sponsors_tier&.draft?
      errors.add(:sponsors_tier, "can not be a draft")
    end
  end
end
