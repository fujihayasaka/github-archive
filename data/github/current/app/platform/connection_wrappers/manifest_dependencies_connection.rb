# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class ManifestDependenciesConnection < ConnectionWrappers::Base
      def nodes
        @items
      end

      def page_info
        return @page_info if defined?(@page_info)
        @page_info = PageInfo.new(**@arguments[:page_info])
      end

      def cursor_for(node)
        node.cursor
      end

      def total_count
        @items.count
      end
    end
  end
end
