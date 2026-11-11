# typed: strict
# frozen_string_literal: true

module Discussions
  module Transfers
    class CandidateRepositoriesComponent < ApplicationComponent
      sig { params(discussion: Discussion, query: T.nilable(String)).void }
      def initialize(discussion:, query: nil)
        @discussion = T.let(discussion, Discussion)
        @query      = T.let(query, T.nilable(String))
      end

      private

      sig { returns(Discussion) }
      attr_reader :discussion

      sig { returns(T.nilable(String)) }
      attr_reader :query

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      sig { returns(T::Array[Repository]) }
      memoize def repositories
        discussion.async_possible_transfer_repositories(
          viewer: current_user,
          query: query,
        ).sync
      end

      sig { returns(String) }
      def empty_results_message
        if query.present?
          "There aren't any eligible repositories that match your query."
        else
          "There aren't any eligible repositories to transfer this discussion to."
        end
      end
    end
  end
end
