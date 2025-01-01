# typed: true
# frozen_string_literal: true

class RepositoryGroupMap < ApplicationRecord::Domain::Repositories
  belongs_to :repository_group
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  validates_presence_of :repository_group, :repository
end
