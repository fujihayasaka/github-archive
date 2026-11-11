# typed: true
# frozen_string_literal: true

# IpmOrganizationMatch represents in-product messaging matches that track organization interactions
# with various product features.
#
# Schema:
# - organization_id: ID of the organization this match belongs to
# - cohort: The cohort this match belongs to
# - metadata: JSON data holding additional information about the match
# - day: The day this match was recorded
class IpmOrganizationMatch < ApplicationRecord::Domain::InProductTargeting
  include GitHub::Relay::GlobalIdentification

  before_validation :set_default_metadata

  validates :organization_id, presence: true
  validates :cohort, presence: true
  validates :day, presence: true

  private

  sig { void }
  def set_default_metadata
    self.metadata = {} if metadata.nil?
  end
end
