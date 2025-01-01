# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    # ### Adds cursor-based pagination to Search::Query
    # This mixin implements Elasticsearch's `search_after` pagination which is more
    # performant than offset-based pagination for large datasets.
    # https://www.elastic.co/guide/en/elasticsearch/reference/current/paginate-search-results.html#search-after
    #
    # It extends basic `search_after` functionality in two ways:
    # - it allows for pagination in both directions (forward and backward)
    #    - Adapted from https://github.com/elastic/elasticsearch/issues/29449
    # - it adds `has_next_page` and `has_previous_page` metadata to the response
    #   - Adapted from https://github.com/elastic/elasticsearch/issues/22364
    #
    module CursorPagination
      class ParameterError < ArgumentError; end

      extend T::Helpers

      abstract!

      SearchAfter = T.type_alias { T::Array[T.any(String, Integer, Float)] }

      class Direction < T::Enum
        enums do
          Forward = new
          Backward = new
        end
      end

      SortField = T.type_alias { T::Hash[T.any(String, Symbol), SortRule::Configuration] }
      Sort = T.type_alias { T::Array[SortField] }

      requires_ancestor { Search::Query }

      sig { params(opts: T::Hash[T.untyped, T.untyped], block: T.nilable(T.proc.void)).void }
      def initialize(opts = {}, &block)
        @direction = T.let(opts[:last] ? Direction::Backward : Direction::Forward, Direction)
        @per_page_with_lookahead = T.let(resolve_per_page!(opts), Integer)
        @search_after = T.let(resolve_search_after!(opts), T.nilable(SearchAfter))
        paginated_opts = opts.merge({ per_page: per_page_with_lookahead })
        super(paginated_opts, &block)

        @sort = T.let(resolve_sort!(opts), Sort)
      end

      # overrides Search::Query#build_sort
      # Sorbet does not support override annotations in modules
      # https://github.com/sorbet/sorbet/issues/7110
      #
      # This provides the object set as the value of the `sort` key in the overall
      # /_search endpoint payload built by `Search::Query#query_document`
      sig { returns(Sort) }
      def build_sort
        @sort.map do |sort_field|
          sort_rule = Search::Queries::SortRule.from_hash(sort_field)
          # Invert the sort rule if we're paginating backward
          # Based on https://github.com/elastic/elasticsearch/issues/29449
          sort_rule.invert! if direction == Direction::Backward
          sort_rule.to_hash
        end
      end

      # overrides Search::Query#query_document
      # Sorbet does not support override annotations in modules
      # https://github.com/sorbet/sorbet/issues/7110
      #
      # This is the overall JSON body that gets passed to the ES /_search endpoint.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def query_document
        result = T.let(super, T::Hash[T.untyped, T.untyped])

        # Exclude a parameter that would otherwise cause us to attempt (inefficient) offset-based pagination.
        # Instead add search_after (if present) to offset results starting point.
        # See https://www.elastic.co/guide/en/elasticsearch/reference/8.6/paginate-search-results.html#search-after
        result.merge!(search_after: search_after) unless search_after.blank?
        result.except(:from)
      end

      # overrides Search::Query#execute to instruct it to return
      # a results class with cursor pagination metadata
      # Sorbet does not support override annotations in modules
      # https://github.com/sorbet/sorbet/issues/7110
      sig do
        params(skip_prune_results: T::Boolean, results_class: T.class_of(Search::Results))
        .returns(Search::Responses::CursorPaginationResponse)
      end
      def execute(skip_prune_results: false, results_class: Responses::CursorPaginationResponse)
        super(skip_prune_results: skip_prune_results, results_class: results_class)
      end

      # overrides Search::Query#build_response
      # Sorbet does not support override annotations in modules
      # https://github.com/sorbet/sorbet/issues/7110
      #
      # Uses the extra result requested via per_page_with_lookahead
      # to determine pagination metadata, then removes
      # it from the results.
      sig do
        params(
          response_class: T.class_of(Search::Results),
          elasticsearch_response: T.nilable(T::Hash[String, T.untyped]),
          options: T::Hash[Symbol, T.untyped],
        )
        .returns(Search::Results[T.untyped])
      end
      def build_response(response_class, elasticsearch_response, options)
        raw_results = elasticsearch_response&.dig("hits", "hits") || []
        # Always override per_page, but don't override other options.
        new_options = {
          has_next_page: has_next_page(raw_results),
          has_previous_page: has_previous_page(raw_results),
        }.merge(options.merge({ per_page: per_page_with_lookahead - 1 }))
        if elasticsearch_response&.dig("hits")
          elasticsearch_response["hits"]["hits"] = remove_lookahead(raw_results)
        end
        response_class.new(elasticsearch_response, new_options)
      end

      sig { abstract.returns(Integer) }
      def max_page_size; end

      sig { abstract.returns(Integer) }
      def default_page_size; end

      sig { abstract.params(opts: T::Hash[T.untyped, T.untyped]).returns(Sort) }
      def resolve_sort!(opts); end

      sig do
        params(opts: T::Hash[T.untyped, T.untyped])
        .returns(T::Hash[Symbol, T.untyped])
      end
      private def per_page_param(opts)
        per_page_opt = opts.delete(:per_page)
        first = opts.delete(:first)
        last = opts.delete(:last)
        if [per_page_opt, first, last].compact.size > 1
          raise ParameterError, "Only one of :per_page, :last, or :first may be specified at a time"
        end
        if last.present? && opts[:after].present?
          raise ParameterError, "Cannot use :last in conjunction with :after"
        end
        if first.present? && opts[:before].present?
          raise ParameterError, "Cannot use :first in conjunction with :before"
        end
        value = per_page_opt || first || last
        param_name = if first
          ":first"
        elsif last
          ":last"
        else
          ":per_page"
        end
        { value:, param_name: }
      end

      sig do
        params(opts: T::Hash[T.untyped, T.untyped])
        .returns(Integer)
      end
      private def resolve_per_page!(opts)
        page_size = per_page_param(opts)
        per_page_int = page_size[:value].try(:to_i)
        valid_per_page = per_page_int&.between?(0, max_page_size)
        if page_size[:value] && !valid_per_page
          raise ParameterError, "#{page_size[:param_name]} must be between 0 and #{max_page_size}"
        end
        raw_per_page = per_page_int || default_page_size
        # We request one extra item so we can determine
        # if has_next_page or has_previous page should be true.
        # Based on https://github.com/elastic/elasticsearch/issues/22364
        raw_per_page + 1
      end

      sig do
        params(opts: T::Hash[T.untyped, T.untyped])
        .returns(T.nilable(SearchAfter))
      end
      private def resolve_search_after!(opts)
        after_cursor = opts[:after]
        before_cursor = opts[:before]
        if after_cursor && before_cursor
          raise ParameterError, "Cannot specify both :before and :after"
        end
        cursor = before_cursor || after_cursor
        begin
          search_after = T.cast(Search::Responses::PropertyEncoder.resolve(cursor), T.nilable(SearchAfter))
        rescue Platform::Errors::Cursor, TypeError
          param_name = after_cursor ? ":after" : ":before"
          raise ParameterError, "#{param_name} does not appear to be a valid cursor"
        end
        search_after
      end

      sig { params(results: T::Array[T.untyped]).returns(T::Boolean) }
      private def has_next_page(results)
        if direction == Direction::Backward
          # If we receive results, :before is a valid cursor from the next page
          !!search_after && results.any?
        else
          # Use the extra result we request to determine if has_next_page
          # should be true.
          # i.e., if we receive the extra item, we know there's another page.
          results.size == per_page_with_lookahead
        end
      end

      sig { params(results: T::Array[T.untyped]).returns(T::Boolean) }
      private def has_previous_page(results)
        if direction == Direction::Backward
          # Use the extra result we request to determine if has_previous_age
          # should be true.
          # i.e., if we receive the extra item, we know there's previous page.
          results.size == per_page_with_lookahead
        else
          # If we receive results, :after is a valid cursor from the previous page
          !!search_after && results.any?
        end
      end

      sig do
        params(raw_results: T::Array[T.untyped])
        .returns(T::Array[T.untyped])
      end
      private def remove_lookahead(raw_results)
        # Remove the extra "look-ahead" result, if it exists.
        results = raw_results.size == per_page_with_lookahead ? raw_results.take(raw_results.size - 1) : raw_results
        # If we're paginating backwards, undo the sort inversion.
        direction == Direction::Backward ? results.reverse : results
      end

      private

      sig { returns(T.nilable(SearchAfter)) }
      attr_reader :search_after

      sig { returns(Integer) }
      attr_reader :per_page_with_lookahead

      sig { returns(Direction) }
      attr_reader :direction
    end
  end
end
