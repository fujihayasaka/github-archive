# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class SearchQuery < ConnectionWrappers::Base
      include CursorGenerator

      class Edge < GraphQL::Pagination::Connection::Edge
        attr_reader :highlights

        def initialize(node, connection, highlights = nil)
          super(node, connection)
          @highlights = highlights
        end
      end

      def skip
        return @skip if defined?(@skip)

        if arguments.present? && arguments[:skip].present?
          @skip = arguments[:skip] < 0 ? 0 : arguments[:skip]
        end
      end

      def edges
        paged_nodes_and_highlights.map do |item|
          Edge.new(item[:node], self, item[:highlights])
        end
      end

      def cursor_for(item)
        offset = starting_offset + nodes.index(item) + 1
        Platform::ConnectionWrappers::CursorGenerator.generate_cursor(offset)
      end

      def has_next_page
        next_offset = starting_offset + limit
        next_page_not_at_max_offset = (next_offset + per_page) <= Search::Query::max_offset_default
        if next_page_not_at_max_offset
          total_count > next_offset
        else
          false
        end
      end
      alias :has_next_page? :has_next_page

      def has_previous_page
        starting_offset > 0
      end
      alias :has_previous_page? :has_previous_page

      # Public: Returns a Search::Results instance for the current query.
      def search_results
        @search_results ||= begin
          @items.execute
        rescue ::Search::Queries::IssueQuery::InsecureUserToServerAppQuery => error
          ::Search::Results.empty(error_message: error.message)
        end
      end

      # A cached count of this search, for API use and internal calculations
      def total_count
        @total_count ||= begin
          @items.count_with_timeout_total
        rescue ::Search::Queries::IssueQuery::InsecureUserToServerAppQuery
          0
        end
      end

      # The offset of the first item in the results. This field along with
      # total count and the nodes size can be used when rendering details about the
      # current page of search results being viewed such as "26-50 of 100".
      def first_item_offset
        starting_offset + 1
      end

      def nodes
        @paged_nodes ||= paged_nodes_and_highlights.map { |item| item[:node] }
      end

      private

      # apply first / last limit results
      def paged_nodes_and_highlights
        @paged_nodes_and_highlights ||= begin
          query_helper = sliced_nodes

          if per_page
            query_helper.per_page = per_page
          end

          if query_limitation_reached?(query_helper)
            []
          else
            results = query_helper.execute

            # We use the query_owning_catalog_service as an allow gate, as only persisted queries (named queries) will have this tag.
            # Hence using it means that the request is hitting the internal graphql controller and it is a query from our react apps, specifically one we own for issues react.
            # Logged out users will see it when the FF is enabled (via dark ship or fully enabling the feature)
            if results.error? && !results.parse_error? && context[:query_owning_catalog_service] == "issues" && (context[:viewer]&.feature_enabled?(:issues_elastic_search_client_error_differentiation) || GitHub.flipper[:issues_elastic_search_client_error_differentiation].enabled?)
              raise Platform::Errors::ServiceUnavailable, "Search is currently unavailable. Error: #{results.error_message}"
            else
              results.map do |item|
                if Elastomer.get_index_name_from_result(item) == "pull-requests"
                  node = item["_model"].pull_request
                else
                  node = item["_model"]
                end
                {
                  node: node,
                  highlights: item["highlight"],
                }
              end
            end
          end
        rescue ::Search::Queries::IssueQuery::InsecureUserToServerAppQuery, ::Search::Query::MaxOffsetError
          []
        end
      end

      # Apply cursors to edges
      def sliced_nodes
        @sliced_nodes ||= begin
          query_helper = @items
          query_helper.configure_page_and_offset(offset: skip ? starting_offset + skip : starting_offset)
          query_helper
        end
        @sliced_nodes
      end

      def offset_from_cursor(cursor)
        resolved_cursor = Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(cursor)

        if resolved_cursor.respond_to?(:to_i)
          resolved_cursor.to_i
        else
          0 # go back to the first result if we don't recognize the cursor
        end
      end

      def starting_offset
        @initial_offset ||= begin
          if before
            [previous_offset, 0].max
          else
            previous_offset
          end
        end
      end

      # Offset from the previous selection, if there was one
      # Otherwise, zero
      def previous_offset
        @previous_offset ||= if after
          offset_from_cursor(after)
        elsif before
          offset_from_cursor(before) - last.to_i - 1
        else
          0
        end
      end

      def per_page
        return @per_page if defined? @per_page

        @per_page = if limit || max_page_size
          [limit, max_page_size].compact.min
        end
      end

      def limit
        @limit ||= if first
          first.to_i
        else
          if previous_offset < 0
            previous_offset + last.to_i
          else
            last.to_i
          end
        end
      end

      # Previously, we have been testing against Search::Query::max_offset_default, even though the actual limit
      # varies between different queries.
      # (See: https://github.com/github/github/blob/66a8845a155e260f27af43cdc54db2ed002444d7/app/platform/connection_wrappers/search_query.rb#L93)
      # This new calculation aims to lift the limit only for issues queries coming through stored operations (e.g.
      # internal GraphQL API calls). See https://github.com/github/issues/issues/8681.
      def query_limitation_reached?(query_helper)
        is_issues_search = query_helper.is_a?(Search::Queries::IssueQuery) || query_helper.is_a?(Search::Queries::ConditionalIssueQuery)
        is_internal = @context[:operation_id].present? && @context[:viewer].present? && @context[:viewer].feature_enabled?(:issues_react_bypass_es_limits)

        if is_issues_search && is_internal
          previous_offset + per_page > query_helper.max_offset
        else
          previous_offset + per_page > Search::Query::max_offset_default
        end
      end
    end
  end
end
