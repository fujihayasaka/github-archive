# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class LabelPullRequests < Resolvers::PullRequests
      filter_by_argument

      def fetch_pull_requests(label, _, _)
        repository = label.repository
        scope = repository.pull_requests.labeled(label.id)
        context[:permission].async_can_list_pull_requests?(repository).then do |can_list_pull_requests|
          filter_scope_by_visibility(scope, repository, can_list_pull_requests)
        end

      end

      def query_components
        [[:label, object.name]]
      end

      def async_repository
        object.async_repository
      end
    end
  end
end
