# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class AuditLogQuery < ConnectionWrappers::Base
      include CursorGenerator

      def initialize(*args, **kwargs)
        super
        protect_against_duplicate_cursor_parameters!
      end

      def cursor_for(item)
        offset = starting_offset + edge_nodes.sync.index(item) + 1
        CursorGenerator.generate_cursor(offset)
      end

      def page_info
        @page_info ||= begin
          synced_nodes = edge_nodes.sync
          PageInfo.new(
            has_next_page: has_next_page,
            has_previous_page: has_previous_page,
            start_cursor: synced_nodes.first ? cursor_for(synced_nodes.first) : nil,
            end_cursor: synced_nodes.last ? cursor_for(synced_nodes.last) : nil,
          )
        end
      end

      def has_next_page
        total_count > starting_offset + limit.to_i
      end

      def has_previous_page
        starting_offset > 0
      end

      def total_count
        @total_count ||= @items.count
      end

      def results
        @results ||= begin
          @items.per_page = limit
          @items.configure_page_and_offset(offset: starting_offset)
          @items.execute
        end
      end

      def edge_nodes
        @edge_nodes ||= ::Promise.resolve(self.results.results)
      end

      private

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
        return unless cursor
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

      # Offset from the previous selection, if there was one
      # Otherwise, zero
      def previous_offset
        @previous_offset ||= if after
          offset_from_cursor(after)
        elsif before
          offset_from_cursor(before) - last.to_i - 1
        elsif last
          total_count - last.to_i
        else
          0
        end
      end

      def protect_against_duplicate_cursor_parameters!
        # We need to build out support for before and after. Until then, let's
        # raise an exception.
        if before.present? && after.present?
          raise Errors::DuplicateBeforeAfterPaginationBoundaries.new
        end
      end
    end
  end
end
