# typed: strict
# frozen_string_literal: true

class IpmRepositoryMatch < ApplicationRecord::Domain::InProductTargeting
  include GitHub::Relay::GlobalIdentification
  self.table_name = "ipm_repository_matches"

  validates :repository_id, presence: true
  validates :cohort, presence: true
  validates :metadata, presence: true
  validates :day, presence: true
end
