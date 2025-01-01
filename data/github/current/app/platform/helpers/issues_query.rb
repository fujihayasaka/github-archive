# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class IssuesQuery
      attr_reader :viewer

      attr_reader :repository

      attr_reader :components

      def initialize(components, viewer:, repository: nil)
        @viewer = viewer
        @components = components
        @repository = repository
      end

      def model_to_be_queried
        ::PullRequest
      end

      def query
        return @query if defined?(@query)
        @query = ::Search::Queries::IssueQuery.new(query_hash)
      end

      private

      def query_hash
        phrase = Search::Queries::IssueQuery.stringify(components)
        { current_user: viewer, phrase: phrase, repo_id: repository&.id }
      end
    end
  end
end
