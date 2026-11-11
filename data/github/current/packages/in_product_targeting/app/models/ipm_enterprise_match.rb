# typed: true
# frozen_string_literal: true

# IpmEnterpriseMatch represents in-product messaging matches that track enterprise interactions
# with various product features.
#
# Schema:
# - enterprise_id: ID of the enterprise this match belongs to
# - cohort: The cohort this match belongs to
# - metadata: JSON data holding additional information about the match
# - day: The day this match was recorded
class IpmEnterpriseMatch < ApplicationRecord::Domain::InProductTargeting # rubocop:disable GitHub/DatabaseModelsShouldHaveTests
  include GitHub::Relay::GlobalIdentification

  validates :enterprise_id, presence: true
  validates :cohort, presence: true
  validates :metadata, presence: true
  validates :day, presence: true
end
