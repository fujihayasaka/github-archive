# typed: true
# frozen_string_literal: true

class RepositoryRecommendationOptOut < ApplicationRecord::Domain::Users
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain

  validates :repository, presence: true
end
