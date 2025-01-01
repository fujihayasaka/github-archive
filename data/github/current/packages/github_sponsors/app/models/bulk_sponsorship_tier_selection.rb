# typed: strict
# frozen_string_literal: true

class BulkSponsorshipTierSelection < ApplicationRecord::Domain::Sponsors
  extend T::Sig

  belongs_to :sponsor, inverse_of: :bulk_sponsorship_tier_selection, class_name: "User"

  before_validation :normalize_sponsors_tier_ids

  validates :sponsor_id, presence: true, uniqueness: true
  validates :sponsors_tier_ids, presence: true
  validate :sponsors_tier_ids_are_valid

  serialize :sponsors_tier_ids, type: Array

  private

  sig { void }
  def normalize_sponsors_tier_ids
    self.sponsors_tier_ids = sponsors_tier_ids.uniq.sort
  end

  sig { void }
  def sponsors_tier_ids_are_valid
    return if sponsors_tier_ids.empty?

    valid_tier_ids = SponsorsTier.where(id: sponsors_tier_ids).pluck(:id).to_set
    invalid_tier_ids = sponsors_tier_ids.to_set - valid_tier_ids

    if invalid_tier_ids.any?
      invalid_summary = invalid_tier_ids.map(&:to_s).sort.to_sentence
      errors.add(:sponsors_tier_ids, "contains invalid tier IDs: #{invalid_summary}")
    end
  end
end
