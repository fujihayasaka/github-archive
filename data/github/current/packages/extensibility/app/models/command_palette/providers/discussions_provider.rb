# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class DiscussionsProvider < ApplicationProvider
      DEFAULT_QUERY = "author:@me"
      IS_VALUES = Search::Queries::DiscussionQuery::IS_VALUES.values.flatten

      def self.modes
        [:owner_repo_references]
      end

      def search(query)
        return [] unless scope_matches?
        return [] unless query_matches_allowed_types?(*IS_VALUES, query: query)
        return search_discussions(DEFAULT_QUERY) if query.blank?
        # if the user is searching by discussion number in the current repo,
        # and we find one, we will return that as the only result.
        if scope.repository?
          discussion_number = query_discussion_number(query)

          if discussion_number.present?
            discussion = find_discussion_by_number(discussion_number)
            return [discussion] unless discussion.nil?
          end
        end

        search_discussions(query)
      end

      def discussion_result(discussion, priority: 2)
        Result.jump_to(discussion, priority: priority, context: context)
      end

      private

      def find_discussion_by_number(number)
        discussion = Discussion.find_by(repository: scope.repository, number: number)
        discussion_result(discussion) if discussion
      end

      # if the user is searching by number (ex: #123), we can find that discussion exactly
      def query_discussion_number(query)
        matches = query.match(/\A(?<number>\d*)\z/)
        matches[:number] if matches.present?
      end

      def search_discussions(query)
        repo = nil

        # include any required additional search parameters here
        search_query = [query]

        if scope.user? || scope.organization?
          search_query << "user:#{scope.owner.login}"
        elsif scope.repository?
          repo = scope.repository
        end

        query = Search::Queries::DiscussionQuery.normalize(
          Search::Queries::DiscussionQuery.parse(search_query.join(" "), current_user),
        )

        search_results = Discussion::SearchResult.search(
          query: query,
          repo: repo,
          page: 1,
          per_page: 10,
          ngram_title: true,
          current_user: current_user,
          user_session: context.user_session,
        )
        search_results.map { |discussion| discussion_result(discussion) }
      end
    end
  end
end
