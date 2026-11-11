# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/EnsureConsistentConnections

module Platform
  module Connections
    class SearchResultItem < Connections::Base
      description "A list of results that matched against a search query. Regardless of the number of matches, a maximum of 1,000 results will be available across all types, potentially split across many pages."

      # Override this to use the `edges` method instead of `edge_node`,
      # since the connection wrapper customized those objects
      def edges
        object.edges
      end

      field :language_aggregates, [Objects::LanguageAggregate], visibility: :internal, description: "The programming languages represented in the search results.", null: false

      def language_aggregates
        @object.search_results.languages
      end

      field :issue_count, Integer, description: "The total number of issues that matched the search query. Regardless of the total number of matches, a maximum of 1,000 results will be available across all types.", null: false
      field :open_issue_count, Integer, visibility: :internal, description: "The total number of open issues that matched the search query. Regardless of the total number of matches, a maximum of 1,000 results will be available across all types.", null: true
      field :closed_issue_count, Integer, visibility: :internal, description: "The total number of closed issues that matched the search query. Regardless of the total number of matches, a maximum of 1,000 results will be available across all types.", null: true

      def open_issue_count
        state_counts = @object.search_results.state_counts
        state_counts.present? && state_counts.has_key?("open") ? state_counts["open"] : nil
      end

      def closed_issue_count
        state_counts = @object.search_results.state_counts
        state_counts.present? && state_counts.has_key?("closed") ? state_counts["closed"] : nil
      end

      def issue_count
        count_if_class(::Search::Queries::IssueQuery)
      end

      field :code_count, Integer, description: "The total number of pieces of code that matched the search query. Regardless of the total number of matches, a maximum of 1,000 results will be available across all types.", null: false

      def code_count
        count_if_class(::Search::Queries::CodeQuery)
      end

      field :marketplace_count, Integer, null: false, visibility: :internal, description: "The total number of 'GitHub Marketplace' or 'Works with GitHub' listings that matched. Regardless of the total number of matches, a maximum of 1,000 results will be available across all types."

      def marketplace_count
        count_if_class(::Search::Queries::MarketplaceQuery)
      end

      field :repository_count, Integer, description: "The total number of repositories that matched the search query. Regardless of the total number of matches, a maximum of 1,000 results will be available across all types.", null: false

      def repository_count
        count_if_class(::Search::Queries::RepoQuery)
      end

      field :user_count, Integer, description: "The total number of users that matched the search query. Regardless of the total number of matches, a maximum of 1,000 results will be available across all types.", null: false

      def user_count
        count_if_class(::Search::Queries::UserQuery)
      end

      field :wiki_count, Integer, description: "The total number of wiki pages that matched the search query. Regardless of the total number of matches, a maximum of 1,000 results will be available across all types.", null: false

      def wiki_count
        count_if_class(::Search::Queries::WikiQuery)
      end

      field :discussion_count, Integer, description: "The total number of discussions that matched the search query. Regardless of the total number of matches, a maximum of 1,000 results will be available across all types.", null: false

      def discussion_count
        count_if_class(::Search::Queries::DiscussionQuery)
      end

      field :issue_search_type, Platform::Enums::IssueSearchType, visibility: {
        public: { environments: [:dotcom] },
        internal: { environments: [:enterprise] },
      }, description: "The type of search that was performed for issues (lexical, semantic, or hybrid)", null: true

      field :lexical_fallback_reason, [Platform::Enums::LexicalFallbackReason], visibility: {
        public: { environments: [:dotcom] },
      }, description: "When a semantic or hybrid search falls back to lexical, the reasons why the fallback occurred.", null: true

      VALID_FALLBACK_REASONS = Platform::Enums::LexicalFallbackReason.values.keys.to_set.freeze

      def lexical_fallback_reason
        return nil unless @object.items.is_a?(::Search::Queries::IssueQuery)
        return nil unless @object.items.respond_to?(:api_fallback_reasons)

        reasons = @object.items.api_fallback_reasons
        return nil if reasons.nil?

        reasons.filter_map { |r| r.to_s.upcase.then { |v| v if VALID_FALLBACK_REASONS.include?(v) } }.presence
      end

      def issue_search_type
        return nil unless @object.items.is_a?(::Search::Queries::IssueQuery)

        if @object.items.respond_to?(:api_search_type)
          @object.items.api_search_type&.upcase || "LEXICAL"
        else
          "LEXICAL"
        end
      end

      private

      # Only return the count if this search is a `search_class` instance.
      # Otherwise return 0.
      def count_if_class(search_class)
        @object.items.is_a?(search_class) ? @object.total_count : 0
      end
    end
  end
end
