# typed: strict
# frozen_string_literal: true

class BulkSponsorshipImport < ApplicationRecord::Domain::Sponsors
  HOURS_UNTIL_EXPIRATION = 24

  belongs_to :sponsor, inverse_of: :bulk_sponsorship_import, class_name: "User"

  validates :sponsor_id, presence: true, uniqueness: true
  validates :data, presence: true

  sig { returns T::Boolean }
  def expired?
    return false unless persisted?
    timestamp = updated_at
    timestamp < HOURS_UNTIL_EXPIRATION.hours.ago
  end
end
