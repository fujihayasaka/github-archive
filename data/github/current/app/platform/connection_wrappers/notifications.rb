# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class Notifications < ConnectionWrappers::Base
      def cursor_for(item)
        index = nodes.index { |node| node.id == item.id }
        offset = starting_offset + index + 1
        CursorGenerator.generate_cursor(offset)
      end

      def has_next_page
        next_offset = starting_offset + limit
        total_count > next_offset
      end

      def has_previous_page
        starting_offset > 0
      end

      def total_count
        @items.count
      end

      # Override the base method as it returns nil when there's no item in the page,
      # breaking the pagination. We still want the cursor to the first item,
      # even when it doesn't exist.
      def start_cursor
        CursorGenerator.generate_cursor([first_item_offset, @items.count + 1].min)
      end

      # The offset of the first item in the results. This field along with
      # total count and the nodes size is used when rendering details about the
      # current page of notifications being viewed such as "26-50 of 100".
      def first_item_offset
        starting_offset + 1
      end

      private

      # Apply limit to results.
      def nodes
        @nodes ||= begin
          query_helper = sliced_nodes
          query_helper.query_options[:per_page] = limit
          query_helper.fetch!
        end
      end

      # Apply cursors.
      def sliced_nodes
        @sliced_nodes ||= begin
          query_helper = @items
          query_helper.query_options[:offset] = starting_offset
          query_helper
        end
      end

      def limit
        @limit ||= if first
          first
        else
          if previous_offset < 0
            previous_offset + last.to_i
          else
            last
          end
        end
      end

      def offset_from_cursor(cursor)
        CursorGenerator.resolve_cursor(cursor).to_i
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

      # Offset from the previous selection, if there was one. Otherwise, zero.
      def previous_offset
        @previous_offset ||= if after
          offset_from_cursor(after)
        elsif before
          offset_from_cursor(before) - last.to_i - 1
        elsif last
          [total_count - last.to_i, 0].max
        else
          0
        end
      end
    end
  end
end
