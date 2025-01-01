# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class RepositoryPullRequests < Resolvers::PullRequests

      filter_by_argument

      def fetch_pull_requests(repo, _, _)
        scope = repo.pull_requests.filter_spam_for(context[:viewer])

        context[:permission].async_can_list_pull_requests?(repo).then do |can_list_pull_requests|
          filter_scope_by_visibility(scope, repo, can_list_pull_requests)
        end
      end

      def query_components
        []
      end

      def async_repository
        Promise.resolve(object)
      end
    end
  end
end
