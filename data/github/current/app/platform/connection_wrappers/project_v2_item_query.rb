# typed: strict
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    # The old implementation for in-memory paging of Memex Project Items from MySQL.
    # This is subject to be deleted once all projects have been transitioned to use the new Elasticsearch
    # backend as part of Memex Without Limits.
    class ProjectV2ItemQuery < ConnectionWrappers::Base
      include GitHub::Memoizer
      extend T::Sig

      sig { returns(MemexProject) }
      attr_reader :memex_project

      sig { returns(Inputs::ProjectV2ItemOrder) }
      attr_reader :order_by

      sig { returns(T::Hash[Integer, String]) }
      attr_reader :item_cursor_map

      sig do
        params(
          memex_project: MemexProject,
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
        memex_project,
        arguments:,
        context:,
        first: nil,
        last: nil,
        after: nil,
        before: nil,
        max_page_size: 100,
        **kwargs
      )
        super(
          nil,
          arguments: arguments,
          first: first,
          last: last,
          after: after,
          before: before,
          max_page_size: max_page_size,
          context: context,
          **kwargs
        )
        @memex_project = memex_project
        @order_by = T.let(arguments[:order_by], Inputs::ProjectV2ItemOrder)
        @item_cursor_map = T.let({}, T::Hash[Integer, String])

        protect_against_duplicate_cursor_parameters!
        check_pagination_arguments!(arguments)
      end

      sig { returns(::Promise[Integer]) }
      def total_count
        async_project_items.then { |items| items.length }
      end

      sig { returns(Promise[T::Array[MemexProjectItem]]) }
      memoize def nodes
        return Promise.resolve(T.let([], T::Array[MemexProjectItem])) if limit.zero?

        async_project_items.then do |items|
          next [] unless items.any? # nothing in the list
          next [] if offset >= items.count # beyond the list

          # populate the item_cursor_map for later use in #cursor_for
          items.each_with_index do |item, index|
            item_id = item.id
            cursor = encode_cursor(index)
            @item_cursor_map[item_id] = cursor if item_id && cursor
          end

          # select only items that are before or after the cursor
          if before
            items = items.first(offset)
          elsif after
            items = items.drop(offset)
          end

          if last
            items.last(last).to_a
          else
            items.first(first).to_a
          end
        end
      end

      sig { returns(::Promise[PageInfo]) }
      memoize def page_info
        nodes.then do |nodes|
          PageInfo.new(
            has_next_page:,
            has_previous_page:,
            start_cursor: cursor_for(nodes.first),
            end_cursor: cursor_for(nodes.last),
          )
        end
      end

      sig { params(item: T.nilable(MemexProjectItem)).returns(Promise[T.untyped]) }
      def cursor_for(item)
        item_id = item&.id
        nodes.then do
          item_cursor_map[item_id] if item_id
        end
      end

      sig { returns(::Promise[T::Boolean]) }
      private def has_next_page
        total_count.then do |total_count|
          if before
            offset < total_count
          elsif last
            false
          elsif after
            offset + limit < total_count
          else
            limit < total_count
          end
        end
      end

      sig { returns(::Promise[T::Boolean]) }
      private def has_previous_page
        total_count.then do |total_count|
          if after
            offset > 0
          elsif before
            (offset - limit) > 0
          elsif last
            limit < total_count
          else
            false
          end
        end
      end

      # Get the smallest, non-nil number to limit the number of project items returned
      sig { returns(Integer) }
      memoize private def limit
        limit = max_page_size

        if first && first < limit
          limit = first
        elsif last && last < limit
          limit = last
        end

        limit
      end

      sig { returns(Integer) }
      memoize private def offset
        if before
          decode_cursor(before).to_i
        elsif after
          # We want to see _after_ the cursor, so increment the skip to bypass that last item
          decode_cursor(after).to_i + 1
        else
          0
        end
      end

      sig { returns(::Promise[T::Array[MemexProjectItem]]) }
      memoize private def async_project_items
        in_memory_backend = Helpers::Projects::InMemoryBackend.new(viewer: context[:viewer])
        in_memory_backend.async_project_items(memex_project:, order_by:)
      end

      sig { params(index: T.nilable(Integer)).returns(T.nilable(String)) }
      private def encode_cursor(index)
        # The original auto-generated ProjectV2ItemConnection encoded the item index as
        # Base64.urlsafe_encode64(index +1, padding: false), without a "cursor:" prefix that
        # CursorGenerator.generate_cursor() method would otherwise add.
        # We'll continue using the same encoding/decoding in ths custom connection for full backwards compatibility.
        Base64.urlsafe_encode64((index + 1).to_s, padding: false) if index
      end

      sig { params(cursor: T.nilable(String)).returns(T.nilable(Integer)) }
      private def decode_cursor(cursor)
        # This performs a simple Base64.urlsafe_decode64() with error handling if "invalid base64".
        CursorGenerator.safe_urlsafe_decode64(cursor).to_i - 1 if cursor
      end

      sig { returns(NilClass) }
      private def protect_against_duplicate_cursor_parameters!
        # We currently do not support both before and after cursors.
        # Until that gets added, let's raise an exception.
        if before.present? && after.present?
          raise Errors::DuplicateBeforeAfterPaginationBoundaries.new
        end
      end

      sig { params(args: T.untyped).returns(NilClass) }
      private def check_pagination_arguments!(args)
        if args[:first].nil? && args[:last].nil? && (args[:before].present? || args[:after].present?)
          raise Platform::Errors::MissingPaginationBoundaries.new(field)
        end
      end
    end
  end
end
