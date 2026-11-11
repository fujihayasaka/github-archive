# typed: strict
# frozen_string_literal: true

class IpmRepositoryMatch < ApplicationRecord::Domain::InProductTargeting
  include GitHub::Relay::GlobalIdentification
  self.table_name = "ipm_repository_matches"

  before_validation :set_default_metadata

  validates :repository_id, presence: true
  validates :cohort, presence: true
  validates :day, presence: true

  private

  sig { void }
  def set_default_metadata
    self.metadata = {} if metadata.nil?
  end
end
