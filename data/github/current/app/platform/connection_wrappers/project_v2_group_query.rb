# typed: strict
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    # The old implementation for in-memory grouping, sorting, filtering, and paging.
    # This is subject to be deleted once all projects have been transitioned to use the new Elasticsearch
    # backend.
    class ProjectV2GroupQuery < ConnectionWrappers::Base
      include GitHub::Memoizer

      ProjectV2GroupQueryEdge = Struct.new(:node, :cursor)

      private_constant :ProjectV2GroupQueryEdge

      sig { returns(GraphQL::Query::Context) }
      attr_reader :context

      sig { returns(Integer) }
      attr_reader :limit

      sig { returns(Integer) }
      attr_reader :offset

      sig { returns(MemexProjectView) }
      attr_reader :memex_project_view

      sig { returns(String) }
      attr_reader :query

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :item_ids

      sig do
        params(
          items: T.untyped,
          arguments: T::Hash[T.untyped, T.untyped],
          context: GraphQL::Query::Context,
          first: T.nilable(Integer),
          last: T.nilable(Integer),
          after: T.nilable(String),
          before: T.nilable(String),
          max_page_size: Integer,
          kwargs: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(
        items,
        arguments:,
        context:,
        first: nil,
        last: nil,
        after: nil,
        before: nil,
        max_page_size: 100,
        **kwargs
      )

        @memex_project_view = T.let(arguments[:memex_project_view], MemexProjectView)

        # If the query argument was completely omitted then we will assume the consumer wants to default
        # to use the filter value stored at the view level. If they did pass in anything then honor exactly
        # what they passed in. The former case (omitted query) is the current mobile experience where it fully
        # relies on the view's persisted state. The new latter case (passing in a query) will be for the new
        # server-side search functionality the mobile team will be looking to implement.
        #
        # The additional #to_s is to ensure that we are always dealing with a string type.
        @query = T.let(arguments.key?(:query) ? arguments[:query].to_s : memex_project_view.filter.to_s, String)

        # Construct our instance
        # The context object used for the project V2 group query.
        @context = T.let(context, GraphQL::Query::Context)
        @limit   = T.let(determine_limit(max_page_size, first, last), Integer)
        @offset  = T.let(determine_offset(last, before, after, field), Integer)

        @item_ids = T.let(arguments[:item_ids], T.nilable(T::Array[Integer]))

        super(
          items,
          arguments: arguments,
          first: first,
          last: last,
          after: after,
          before: before,
          max_page_size: max_page_size,
          context: context,
          **kwargs
        )
      end

      # Note: This works with the existing in-memory implementation but this might need reconsideration
      # for the upcoming Elasticsearch backend as counting the total number of groups might be expensive.
      # We may need to either move to approximate counts or remove counting altogether if possible.
      sig { returns(::Promise[Integer]) }
      def total_count
        async_groups.then { |project_grouped_view_items| project_grouped_view_items.length }
      end

      sig { returns(T.any(::Promise[T::Array[ProjectV2GroupQueryEdge]], ::Promise[[]])) }
      memoize def edges
        return ::Promise.resolve([]) if limit.zero?

        async_groups.then do |groups|
          next [] unless groups.any? # nothing in the list
          next [] if offset >= groups.count # beyond the list

          start_index = offset
          end_index = offset + limit - 1
          paged_project_groups = groups[start_index..end_index].to_a

          paged_project_groups.map.with_index do |group, index|
            cursor = CursorGenerator.generate_cursor(offset + index, version: :v2)
            ProjectV2GroupQueryEdge.new(group, cursor)
          end
        end
      end

      sig { returns(::Promise[T::Array[Platform::Models::ProjectGroup]]) }
      memoize def edge_nodes
        edges.then { |edges| edges.map(&:node) }
      end

      sig { returns(::Promise[PageInfo]) }
      memoize def page_info
        edges.then do |edges|
          PageInfo.new(
            has_next_page:,
            has_previous_page:,
            start_cursor: edges.first&.cursor,
            end_cursor: edges.last&.cursor,
          )
        end
      end

      # We can hard-code this since this connection wrapper only uses MySQL.
      sig { returns(T::Boolean) }
      def fulfilled_via_elasticsearch?
        false
      end

      sig { override.params(group: Models::ProjectGroup).returns(Promise[T.nilable(String)]) }
      def cursor_for(group)
        edges.then do |edges|
          edges.find { |edge| edge.node == group }&.cursor
        end
      end

      private

      sig { returns(::Promise[T::Boolean]) }
      def has_next_page
        total_count.then do |total_count|
          offset + limit < total_count
        end
      end

      sig { returns(T::Boolean) }
      def has_previous_page
        offset > 0
      end

      sig do
        params(
          last: T.nilable(Integer),
          before: T.nilable(String),
          after: T.nilable(String),
          field: T.nilable(GraphQL::Schema::Field)
        ).returns(Integer)
      end
      def determine_offset(last, before, after, field)
        if last
          raise Errors::MissingBackwardsPaginationArgument.new(field) unless before

          offset = decode_cursor(before).to_i
          offset -= last
        elsif after
          offset = decode_cursor(after).to_i
          # We want to see _after_ the cursor, so increment the skip to bypass that commit
          offset += 1
        else
          offset = 0
        end

        offset
      end

      # Taken from app/platform/connection_wrappers/commit_history.rb
      # Get the smallest, non-nil number
      sig { params(max_page_size: Integer, first: T.nilable(Integer), last: T.nilable(Integer)).returns(Integer) }
      def determine_limit(max_page_size, first, last)
        limit = max_page_size

        if first && first < limit
          limit = first
        elsif last && last < limit
          limit = last
        end

        limit
      end

      sig { returns(::Promise[T::Array[Platform::Models::ProjectGroup]]) }
      memoize def async_groups
        in_memory_backend = Helpers::Projects::InMemoryBackend.new(viewer: context[:viewer])
        in_memory_backend.async_groups(memex_project_view, query:, item_ids:)
      end

      sig { params(cursor: T.nilable(String)).returns(T.nilable(Integer)) }
      def decode_cursor(cursor)
        CursorGenerator.resolve_cursor(cursor) if cursor
      end
    end
  end
end
