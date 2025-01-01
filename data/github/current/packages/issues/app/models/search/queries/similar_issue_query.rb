# typed: true
# frozen_string_literal: true

require "set"

module Search
  module Queries
    class SimilarIssueQuery < IssueQuery

      def self.field_list
        [:repo]
      end

      def self.unique_field_list
        []
      end

      IS_VALUES = {}
      SORT_MAPPINGS = {}

      # Internal: Normalize terms in parsed query.
      #
      # Removes duplicate terms preferring the right-most term.
      #
      # ary - Parsed query Array
      #
      # Returns Array.
      def self.normalize(query_terms)
        super(query_terms)
      end

      # Construct an IssueQuery. The query can be restricted to a single
      # language by providing a :language option. The query can also be
      # restricted to a single repository by providing the :repo_id option.
      #
      # opts - The options Hash.
      #   :repo_id  - The Repository ID to filter by
      #
      def initialize(opts = {}, &block)
        super(opts, &block)

        @index = Elastomer::Indexes::Issues.searcher
        @repo_id = opts.fetch(:repo_id, nil)
        @type = "issues"
      end

      # Internal: Constructs the actual `:query` portion of the query
      # document. This will later be wrapped in a filtered query if search
      # qualifiers were also used.
      #
      # Returns the search query Hash.
      def query_doc
        return if escaped_query.empty?

        {
          multi_match: {
            query: escaped_query,
            fields: %w[title^1.5 body],
          },
        }
      end

      def build_sort; end

      def build_highlight; end

      def build_filter; end

      def build_aggregations; end
    end
  end
end
