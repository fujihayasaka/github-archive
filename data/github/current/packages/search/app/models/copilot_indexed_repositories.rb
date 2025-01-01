# typed: strict
# frozen_string_literal: true

class CopilotIndexedRepositories < ApplicationRecord::Domain::Copilot
  include GitHub::Memoizer
  extend GitHub::ResilienceMixin

  DEFAULT_COPILOT_INDEXING_QUOTA = 50
  DEFAULT_COPILOT_INDIVIDUAL_INDEXING_QUOTA = 5

  belongs_to :organization
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  destroy_in_background_with :repository

  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :name_validation_only

  sig { params(repo: Repository).returns(T.nilable(CopilotIndexedRepositories)) }
  def self.for_repository(repo)
    with_database_error_fallback(fallback: nil) do
      find_by(repository_id: repo.id)
    end
  end

  # Returns true if the repository is indexed for semantic code search in blackbird.
  sig { returns(T::Boolean) }
  def semantic_code_search_ok?
    blackbird_status.semantic_code_search_ok
  end

  private

  # We need to load this to allow sorbet to know about the proto types in the `sig` for `blackbird_status`.
  BlackbirdClient = BlackbirdSearch::Client

  # High level summary status of this repository in Blackbird. On error, or if the repository is not indexed or had an
  # error indexing, returns `RepositoryStatus` with all status booleans set to false. If you need more detail about
  # the state of a repository in blackbird, call `BlackbirdClient.get_repository_status` directly.
  sig { returns(Blackbird::Query::V1::RepositoryStatus) }
  memoize def blackbird_status
    resp = BlackbirdClient.get_repository_status([repository_id])
    if resp.error
      err = T.must(resp.error)
      GitHub.logger.error("blackbird get_repository_status failed", "blackbird.error.code": err.code, "blackbird.error.msg": err.msg, "blackbird.error.repo_id": repository_id)
      # NB: All status booleans are set to false by default on this:
      Blackbird::Query::V1::RepositoryStatus.new(repository_id: repository_id)
    else
      resp.data.repositories.first
    end
  end
end
