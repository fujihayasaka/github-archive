# typed: strict
# frozen_string_literal: true

module PullRequests
  class Domain < GH::Domain::Base
    # Cached version of repository#open_pull_request_count_for
    # TODO: remove #open_pull_request_count_for from Repository and implement the method here instead,
    # downgrading to non-AR arguments
    sig { params(repository: ::Repository, viewer: T.nilable(::User)).returns(Numeric) }
    def open_pull_request_count_for_repo(repository, viewer)
      count = PullRequests::Cache::OpenPullRequestCountClient.new(repository, viewer).fetch do
        repository.open_pull_request_count_for(viewer)
      end

      # if the count was fetched from cache, we need to set it on the repository
      repository.set_open_pull_request_count_for(viewer, count)
      count
    end

    # Returns IDs of open pull requests matching the given head_ref, head_sha, and head_repository_id.
    sig { params(repository: ::Repository, head_ref: T.any(String, T::Array[String]), head_sha: String, head_repository_id: Integer).returns(T::Array[Integer]) }
    def open_pull_request_ids_for_head(repository, head_ref:, head_sha:, head_repository_id:)
      repository.pull_requests.open_pulls
        .where(head_ref: head_ref, head_sha: head_sha, head_repository_id: head_repository_id)
        .order(id: :desc)
        .pluck(:id)
    end

    # Returns the first open pull request for a repository matching the given head_sha, or nil.
    sig { params(repository: ::Repository, head_sha: String).returns(T.nilable(::PullRequest)) }
    def find_open_pull_request_by_head_sha(repository, head_sha:)
      repository.pull_requests.open_pulls.where(head_sha: head_sha).first
    end
  end
end
