# typed: strict
# frozen_string_literal: true

class BulkSponsorshipImport < ApplicationRecord::Domain::Sponsors
  extend T::Sig

  HOURS_UNTIL_EXPIRATION = 24

  belongs_to :sponsor, inverse_of: :bulk_sponsorship_import, class_name: "User"

  validates :sponsor_id, presence: true, uniqueness: true
  validates :data, presence: true

  sig { returns T::Boolean }
  def expired?
    return false unless persisted?
    timestamp = T.must_because(updated_at) { "field is non-nil in the database" }
    timestamp < HOURS_UNTIL_EXPIRATION.hours.ago
  end
end
