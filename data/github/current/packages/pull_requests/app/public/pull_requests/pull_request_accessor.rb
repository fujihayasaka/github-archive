# typed: strict
# frozen_string_literal: true

module PullRequests
  class PullRequestAccessor
    # Public: Load a pull request by its number, scoped to the given repository id.
    #
    # Returns an IPullRequest.
    #
    # Raises GH::Errors::ObjectNotFound
    sig { params(repository_id: Integer, number: Integer).returns(IPullRequest) }
    def by_number(repository_id:, number:)
      issue = Issue.find_by(number: number, repository_id: repository_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      pull = issue&.pull_request

      if pull.nil?
        raise GH::Errors::ObjectNotFound.new(expected_type: IPullRequest)
      end

      pull
    end

    # Public: Load a pull request that was merged by a specific commit, given
    # the repository, base branch, and full OID of the merge commit.
    #
    # Returns an IPullRequest if found, or nil if not found.
    sig do
      params(
        repository_id: Integer,
        base_branch_name: String,
        oid: String,
      ).returns(T.nilable(IPullRequest))
    end
    def by_merge_commit(repository_id:, base_branch_name:, oid:)
      index = Elastomer::Indexes::PullRequests.new
      result, id =
        index.id_by_merge_commit(
          repository_id: repository_id,
          base_branch_name: base_branch_name,
          oid: oid,
        )

      if result == :timed_out
        raise GH::Errors::DataStoreUnavailableError
      elsif id
        PullRequest.find_by(id: id)
      end
    end

    # Public: Load merged pull requests by their IDs, scoped to a repository.
    # Only returns PRs that have been merged and have a non-nil merge_commit_sha.
    #
    # Returns PullRequest AR objects (not IPullRequest) because callers need
    # merge_commit_sha which is not on the interface.
    sig do
      params(
        pull_request_ids: T::Array[Integer],
        repository_id: Integer,
        limit: Integer,
      ).returns(T::Array[::PullRequest])
    end
    def merged_by_ids(pull_request_ids:, repository_id:, limit: 10)
      return [] if pull_request_ids.empty?

      ::PullRequest
        .where(id: pull_request_ids, repository_id: repository_id)
        .where.not(merged_at: nil)
        .where.not(merge_commit_sha: nil)
        .order(merged_at: :desc)
        .limit(limit)
        .to_a
    end
  end
end
