# typed: false
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    def gh_stafftools_repository_pull_requests_path(repo)
      expand_nwo_from :stafftools_repository_pull_requests_path, repo
    end

    def gh_purge_stafftools_repository_pull_requests_path(repo)
      expand_nwo_from :purge_stafftools_repository_pull_requests_path, repo
    end

    def gh_reindex_stafftools_repository_pull_requests_path(repo)
      expand_nwo_from :reindex_stafftools_repository_pull_requests_path, repo
    end

    def gh_stop_stafftools_repository_pull_requests_path(repo)
      expand_nwo_from :stop_stafftools_repository_pull_requests_path, repo
    end

    def gh_sync_search_index_stafftools_repository_pull_request(pr)
      expand_from_pr :sync_search_index_stafftools_repository_pull_request_path, pr
    end

    def gh_stafftools_repository_pull_request_path(pr)
      expand_from_pr :stafftools_repository_pull_request_path, pr
    end

    def gh_close_stafftools_repository_pull_request_path(pr)
      expand_from_pr :close_stafftools_repository_pull_request_path, pr
    end

    def gh_merge_stafftools_repository_pull_request_path(pr)
      expand_from_pr :merge_stafftools_repository_pull_request_path, pr
    end

    def gh_open_stafftools_repository_pull_request_path(pr)
      expand_from_pr :open_stafftools_repository_pull_request_path, pr
    end

    def gh_database_stafftools_repository_pull_request_path(pr)
      expand_from_pr :database_stafftools_repository_pull_request_path, pr
    end

    def gh_sync_stafftools_repository_pull_request_path(pr)
      expand_from_pr :sync_stafftools_repository_pull_request_path, pr
    end

    def gh_stafftools_repository_pull_request_subscriptions_path(pr)
      expand_from_pr :stafftools_repository_pull_request_subscriptions_path, pr
    end

    private

    def expand_from_pr(helper, pr)
      repo = pr.repository
      send(helper, repo.owner, repo.name, pr.number)
    end

  end
end
