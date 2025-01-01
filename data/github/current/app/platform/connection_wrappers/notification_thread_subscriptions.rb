# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class NotificationThreadSubscriptions < ConnectionWrappers::Base

      def cursor_for(object)
        CursorGenerator.generate_cursor(object.id)
      end

      def start_cursor
        edge_nodes.first ? cursor_for(edge_nodes.first) : nil
      end

      def end_cursor
        edge_nodes.last ? cursor_for(edge_nodes.last) : nil
      end

      def has_next_page
        last ? page_object.has_previous_page : page_object.has_next_page
      end

      def has_previous_page
        last ? page_object.has_next_page : page_object.has_previous_page
      end

      def edge_nodes
        @edge_nodes ||= begin
          nodes = page_object.page
          nodes = nodes.reverse if last
          nodes
        end
      end

      def total_count
        @items.total_count
      end

      alias :has_next_page? :has_next_page
      alias :has_previous_page? :has_previous_page

      private

      def page_object
        @page_object ||= @items.fetch!(cursor: id_cursor, limit: limit, direction: query_direction)
      end

      # Returns Integer ID encoded within the string cursor argument.
      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def id_cursor
        @id_cursor ||= (cursor = after || before) && CursorGenerator.resolve_cursor(cursor).to_i
      end
      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

      def limit
        first || last
      end

      def query_direction
        @query_direction = last ? invert_direction(@items.direction) : @items.direction
      end

      def invert_direction(direction)
        direction == :desc ? :asc : :desc
      end
    end
  end
end
