# typed: true
# frozen_string_literal: true

class RepositoryMilestonesSequence < ApplicationRecord::Domain::IssuesPullRequests
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain return_type: T.nilable(Repositories::IRepository)
end
