# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers

    # This connection wrapper queries Newsies APIs and then returns ActiveRecord
    # models back via the platform loaders. This is how we return User objects
    # from the watching/watchers connections.
    class Newsies < ConnectionWrappers::Base
      def initialize(relation, **kwargs)
        super(relation.dup, **kwargs)
        @ids = nil
        @edge_nodes = nil
        @page_info = nil
        @has_previous_page = nil
        @has_next_page = nil
        @newsies_direction = nil
        @newsies_cursor = nil
        protect_against_duplicate_cursor_parameters!
      end

      def cursor_for(item)
        if item.is_a? ::Promise
          item.then { |result| encode_cursor(result.id) }
        else
          encode_cursor(item.id)
        end
      end

      def page_info
        load_edge_ids
        @page_info
      end

      def edge_nodes
        @edge_nodes ||= begin
          load_edge_ids

          # When fetching from Newsies, we assume that the returned IDs are
          # fetchable by ActiveRecord (since they live in a separate database).
          # Here, we use a loader to batch the query in order to avoid refetching
          # any records.
          ::Promise.all(@ids.map { |id| Loaders::ActiveRecord.load(@items.model_to_be_queried, id) })
        end
      end

      def has_next_page
        if @has_next_page.nil?
          @has_next_page = load_reverse_pagination_check
        end
        @has_next_page
      end

      def has_previous_page
        if @has_previous_page.nil?
          @has_previous_page = load_reverse_pagination_check
        end
        @has_previous_page
      end

      def total_count
        @items.count
      end

      private

      def build_page_info(ids:)
        PageInfo.new(
          start_cursor: encode_cursor(ids.first),
          end_cursor: encode_cursor(ids.last),
          connection: self,
        )
      end

      def protect_against_duplicate_cursor_parameters!
        # We need to build out support for before and after. Until then, let's
        # raise an exception.
        if before.present? && after.present?
          raise Errors::DuplicateBeforeAfterPaginationBoundaries.new
        end
      end

      def encode_cursor(cursor)
        CursorGenerator.generate_cursor(cursor)
      end

      def decode_cursor(cursor)
        CursorGenerator.resolve_cursor(cursor)
      end

      # Access Newsies to load the specified Ids into `@ids`
      #
      # It also loads:
      #  - Forward-pagination check into `@has_next_page` or `@has_previous_page`
      #  - `@page_info`
      #
      # Returns nothing
      def load_edge_ids
        return @ids if @ids

        # Depending on if first or last has been passed, set the offset.
        if before.present?
          @newsies_cursor = decode_cursor(before)
          @newsies_direction = :downwards
        elsif after.present?
          @newsies_cursor = decode_cursor(after)
          @newsies_direction = :upwards
        else
          @newsies_cursor = nil
          if last.present?
            @newsies_direction = :downwards
          elsif first.present?
            @newsies_direction = :upwards
          end
        end

        edges_limit = (first || last)
        # Add 1 to the limit so we can see if there are any beyond this page
        newsies_limit = edges_limit + 1

        ids = load_newsies(@newsies_cursor, @newsies_direction, newsies_limit)

        @page_info = build_page_info(ids: ids)

        has_more_records = ids.length > edges_limit
        forward_pagination = first.present?
        backward_pagination = last.present?

        # Slice off the extra record we loaded in order to check for pagination
        if has_more_records
          if forward_pagination
            ids = ids.first(first)
          elsif backward_pagination
            ids = ids.last(last)
          end
        end

        if forward_pagination
          @has_previous_page = false if after.nil?
          @has_next_page = has_more_records
        elsif backward_pagination
          @has_previous_page = has_more_records
          @has_next_page = false if before.nil?
        end

        @ids = ids
      end

      # Returns an array of IDs
      def load_newsies(cursor, direction, limit)
        query = @items.dup
        # The cursor may be nil for the end of the list
        if cursor
          query.cursor = cursor
        end
        query.cursor_direction = direction
        query.limit = limit
        query.fetch!
      end

      # Check if there are any items at all
      # in the _opposite_ direction of this relation
      def load_reverse_pagination_check
        load_edge_ids
        cursor_direction = @newsies_direction == :downwards ? :upwards : :downwards
        reverse_ids = load_newsies(@newsies_cursor, cursor_direction, 1)
        reverse_ids.any?
      end
    end
  end
end
