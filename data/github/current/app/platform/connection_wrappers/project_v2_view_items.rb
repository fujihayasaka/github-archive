# typed: strict
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    # This is for backwards-compatibility with the in-memory Ruby implementation for grouping, sorting, paging,
    # and filtering. It is subject to removal once the new Memex Without Limits backend is fully rolled out
    # and the current one has been sunset.
    class ProjectV2ViewItems < ConnectionWrappers::Base
      include GitHub::Memoizer

      ProjectV2ViewItemsEdge = Struct.new(:node, :cursor)

      private_constant :ProjectV2ViewItemsEdge

      sig { returns(Integer) }
      attr_reader :limit

      sig { returns(Integer) }
      attr_reader :offset

      sig { returns(Models::ProjectGroup) }
      attr_reader :project_group

      sig do
        params(
          items: T.untyped,
          arguments: T::Hash[T.untyped, T.untyped],
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
        first: nil,
        last: nil,
        after: nil,
        before: nil,
        max_page_size: 100,
        **kwargs
      )
        @project_group = T.let(arguments[:project_group], Models::ProjectGroup)

        @limit = T.let(determine_limit(max_page_size, first, last), Integer)
        @offset = T.let(determine_offset(last, before, after), Integer)
        super(
          items,
          arguments: arguments,
          first: first,
          last: last,
          after: after,
          before: before,
          max_page_size: max_page_size,
          **kwargs
        )
      end

      sig { returns(Integer) }
      def total_count
        project_group.items.count
      end

      sig { returns(T::Array[ProjectV2ViewItemsEdge]) }
      memoize def edges
        return [] if limit.zero?
        return [] unless project_group.items.any? # nothing in the list
        return [] if offset >= total_count # beyond the list

        start_index = offset
        end_index = offset + limit - 1
        paged_view_items = project_group.items[start_index..end_index].to_a

        paged_view_items.map.with_index do |view_item, index|
          cursor = CursorGenerator.generate_cursor((offset + index), version: :v2)
          ProjectV2ViewItemsEdge.new(view_item, cursor)
        end
      end

      sig { returns(T::Array[Models::ProjectGroup]) }
      memoize def edge_nodes
        edges.map(&:node)
      end

      sig { returns(PageInfo) }
      memoize def page_info
        PageInfo.new(
          has_next_page:,
          has_previous_page:,
          start_cursor: cursor_for(edges.first&.node),
          end_cursor: cursor_for(edges.last&.node),
        )
      end

      sig { override.params(view_item: T.nilable(Models::ProjectViewItem)).returns(T.nilable(String)) }
      def cursor_for(view_item)
        if view_item
          index = project_group.items.index(view_item)
          CursorGenerator.generate_cursor((offset + index), version: :v2)
        end
      end

      private

      sig { returns(T::Boolean) }
      def has_next_page
        offset + limit < total_count
      end

      sig { returns(T::Boolean) }
      def has_previous_page
        offset > 0
      end

      sig do
        params(
          last: T.nilable(Integer),
          before: T.nilable(String),
          after: T.nilable(String)
        ).returns(Integer)
      end
      def determine_offset(last, before, after)
        if last
          raise Errors::MissingBackwardsPaginationArgument.new(nil) unless before

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

      sig { params(cursor: T.nilable(String)).returns(T.nilable(Integer)) }
      def decode_cursor(cursor)
        CursorGenerator.resolve_cursor(cursor) if cursor
      end
    end
  end
end
