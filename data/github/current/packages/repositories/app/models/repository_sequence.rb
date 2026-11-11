# typed: strict
# frozen_string_literal: true

class RepositorySequence < ApplicationRecord::Domain::Repositories
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
end
