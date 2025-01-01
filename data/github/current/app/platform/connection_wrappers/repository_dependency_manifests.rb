# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class RepositoryDependencyManifests < ArrayWrapper
      attr_accessor :has_next_page, :has_previous_page, :start_cursor, :end_cursor, :total_count

      def load_nodes
        @nodes ||= items
      end
    end
  end
end
