# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class ProjectCards < ConnectionWrappers::Base
      def connection
        @connection ||= @items.connection(
          field: @field,
          max_page_size: @max_page_size,
          parent: @parent,
        )
      end

      def cursor_for(item)
        connection.then { |connection| connection.cursor_for(item) }
      end

      def edge_nodes
        connection.then(&:edge_nodes)
      end

      def page_info
        connection.then(&:page_info)
      end

      def nodes
        connection.then(&:paged_nodes)
      end

      def total_count
        @total_count ||= @items.total_count
      end
    end
  end
end
