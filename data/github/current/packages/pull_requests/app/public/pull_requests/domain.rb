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
  end
end
