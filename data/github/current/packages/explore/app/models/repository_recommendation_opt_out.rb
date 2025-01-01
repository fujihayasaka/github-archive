# typed: true
# frozen_string_literal: true

class RepositoryRecommendationOptOut < ApplicationRecord::Domain::Users
  belongs_to :repository

  validates :repository, presence: true
end
