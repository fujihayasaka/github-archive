# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class IssuesProvider < ApplicationProvider
      DEFAULT_QUERY = "author:@me"
      IS_VALUES = Search::Queries::IssueQuery::IS_VALUES.values.flatten

      def self.modes
        [:owner_repo_references, :global_references]
      end

      def search(query)
        return [] unless scope_matches?
        return [] unless query_matches_allowed_types?(*IS_VALUES, query: query)
        return search_issues_and_prs(DEFAULT_QUERY) if query.blank?

        # if the user is searching by issue number in the current repo,
        # and we find one, we will return that as the only result.
        if scope.repository?
          issue_number = query_issue_number(query)

          if issue_number.present?
            issue = find_issue_by_number(issue_number)
            return [issue] unless issue.nil?
          end
        end

        search_issues_and_prs(query)
      end

      def issue_result(issue, priority: 2)
        Result.jump_to(issue, priority: priority, context: context)
      end

      private

      def find_issue_by_number(number)
        issue = Issue.find_by(repository: scope.repository, number: number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        issue_result(issue) if issue
      end

      # if the user is searching by number (ex: #123), we can find that issue exactly
      def query_issue_number(query)
        matches = query.match(/\A(?<number>\d*)\z/)
        matches[:number] if matches.present?
      end

      def search_issues_and_prs(query)
        params = {
          current_user: current_user,
          user_session: context.user_session,
          per_page: 10,
          ngram_title: true,
          context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
        }

        # include any required additional search parameters here
        search_query = [query, "archived:false"]

        if scope.object.is_a?(User) # also is true for Organizations
          search_query << "user:#{scope.owner.login}"
        elsif scope.repository?
          params[:repo] = scope.repository
        end

        tags = []
        tags << "controller:#{GitHub.context[:controller]}" if GitHub.context[:controller]
        tags << "action:#{GitHub.context[:controller_action]}" if GitHub.context[:controller_action]
        params[:tags] = tags if tags.any?

        search_results = Issue::SearchResult.search(query: search_query.join(" "), **params)
        search_results[:issues].map { |issue| issue_result(issue) }
      end
    end
  end
end
