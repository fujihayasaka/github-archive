# typed: true
# frozen_string_literal: true

require "set"

module Search
  module Queries

    class CursorPaginatedConditionalIssueQuery < ::Search::Queries::ConditionalIssueQuery
      include CursorPagination

      DEFAULT_PER_PAGE = 30
      MAX_PER_PAGE = 100

      def initialize(opts, &block)
        super(opts, &block)
      end

      def build_sort
        # super refers to just the build_sort method in the CursorPagination modul(e
        ary = T.cast(super, T::Array[T.any(SortField, String)])

        # Similar to build_sort in the IssueQuery grandparent class, we're evaluating the date fields in
        # sort, and ensuring they are declared as an unmapped type (date) - so missing data is handled correctly
        ary.each do |item|
          next unless item.is_a?(Hash)

          key = item.keys.first

          if :created_at == key || :updated_at == key
            T.must(item[key])[:unmapped_type] = "date"
          end
        end

        ary
      end

      sig { params(value: T.nilable(T::Array[String])).void }
      def sort=(value)
        # When sort is called with a string array [created_at, desc] for instance
        # Convert this into a a hash that can be used by elastic
        @sort = build_sort_section(value || [], SORT_MAPPINGS)
      end

      sig { override.returns(Integer) }
      def default_page_size
        DEFAULT_PER_PAGE
      end

      sig { override.returns(Integer) }
      def max_page_size
        MAX_PER_PAGE
      end

      sig { override.params(opts: T::Hash[Symbol, T.untyped]).returns(Sort) }
      def resolve_sort!(opts)
        # Build sort using either the opts, or the sort getter

        sort_ = [] + (opts.fetch(:sort, sort) || []) + %w[_score desc]
        raw_sort = Array.wrap(build_sort_section(sort_, SORT_MAPPINGS))

        (raw_sort || []) + [
          {
            # This is a tiebreaker sort value that's guaranteed to be unique for each item (in this case the id of the issue)
            #
            # Tiebreakers are recommended when not querying with Point In Time
            # (PIT) queries add an implicit tie-breaker, but they can generate stale
            # results, so we've opted not to use them.
            #
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/paginate-search-results.html#search-after
            issue_id: "desc"
          }
        ]
      end

      def query_document
        result = super

        if search_after.blank? && page.present? && per_page.present?
          # for cursor pagination we increase per_page by 1 to see if we have a next page
          # here we override the correct offset if we need it for offset-based pagination
          from = [0, (page - 1) * (per_page - 1)].max
          result.merge!(from: from)
          result
        else
          result
        end
      end

      def has_previous_page(raw_results)
        super || !!(page && page > 1)
      end
    end
  end
end
