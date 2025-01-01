# typed: strict
# frozen_string_literal: true

class CopilotIndexedRepositories < ApplicationRecord::Domain::Copilot
  include GitHub::Memoizer

  DEFAULT_COPILOT_INDEXING_QUOTA = 50
  DEFAULT_COPILOT_INDIVIDUAL_INDEXING_QUOTA = 5
  MAX_INDEXED_REPOS = 500000

  belongs_to :organization
  belongs_to :repository
  destroy_in_background_with :repository

  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :name_validation_only

  # Returns true if the repository is indexed for semantic code search in blackbird.
  sig { returns(T::Boolean) }
  def semantic_code_search_ok?
    blackbird_status.semantic_code_search_ok
  end

  # Returns true if the repository is indexed for semantic doc search in blackbird. Note that semantic code search is
  # inclusive of doc search (but not the other way around).
  sig { returns(T::Boolean) }
  def semantic_doc_search_ok?
    blackbird_status.semantic_doc_search_ok
  end

  private

  # We need to load this to allow sorbet to know about the proto types in the `sig` for `blackbird_status`.
  BlackbirdClient = Search::Blackbird::Client

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
