# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class CursorPaginatedRepoQuery < ::Search::Queries::RepoQuery
      include CursorPagination

      DEFAULT_PAGE_SIZE = 100
      MAX_PAGE_SIZE = 250

      def max_page_size
        MAX_PAGE_SIZE
      end

      def default_page_size
        DEFAULT_PAGE_SIZE
      end

      # This method converts the sort options into a format that is used by the CursorPagination module.
      # repo_id is used as a tiebreaker sort.
      #
      # Examples:
      #
      #   resolve_sort!( { phrase: "sort:updated" } )
      #   #=> [{'pushed_at' => 'desc'}, {'repo_id' => 'asc'}]
      #
      #   resolve_sort!( { phrase: "sort:updated sort:name-asc" } )
      #   #=> [{'pushed_at' => 'desc'}, {'name_sort' => 'asc'}, {'repo_id' => 'asc'}]
      sig { override.params(opts: T::Hash[Symbol, String]).returns(Sort) }
      def resolve_sort!(opts)
        sort_output = []

        sort_method_output = sort
        if sort_method_output.present?
          # Use build_sort_section to map Array tuple input (["updated", "desc"])
          #   to mapped output Hash ({ "pushed_at" => "desc" })
          built_sort = build_sort_section(sort_method_output, SORT_MAPPINGS)
          sort_output.push(built_sort)
        end

        sort_output.push({
          # This is a tiebreaker sort value that's guaranteed to be unique for each item
          #
          # Tiebreakers are recommended when not querying with Point In Time
          # (PIT) queries add an implicit tie-breaker, but they can generate stale
          # results, so we've opted not to use them.
          #
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/paginate-search-results.html#search-after
          "repo_id" => "asc"
        })

        sort_output.compact.flatten
      end
    end
  end
end
