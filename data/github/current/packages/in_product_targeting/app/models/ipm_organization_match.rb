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
class IpmOrganizationMatch < ApplicationRecord::Domain::InProductTargeting # rubocop:disable GitHub/DatabaseModelsShouldHaveTests
  include GitHub::Relay::GlobalIdentification

  validates :organization_id, presence: true
  validates :cohort, presence: true
  validates :metadata, presence: true
  validates :day, presence: true
end
