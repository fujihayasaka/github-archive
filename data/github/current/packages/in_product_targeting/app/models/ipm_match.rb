# typed: true
# frozen_string_literal: true

# IpmMatch represents in-product messaging matches that track user interactions
# with various product features.
#
# Schema:
# - user_id: ID of the user this match belongs to
# - cohort: The cohort this match belongs to
# - metadata: JSON data holding additional information about the match
# - day: The day this match was recorded
class IpmMatch < ApplicationRecord::Domain::InProductTargeting
  include GitHub::Relay::GlobalIdentification

  before_validation :set_default_metadata

  validates :user_id, presence: true
  validates :cohort, presence: true
  validates :day, presence: true

  private

  sig { void }
  def set_default_metadata
    self.metadata = {} if metadata.nil?
  end
end
