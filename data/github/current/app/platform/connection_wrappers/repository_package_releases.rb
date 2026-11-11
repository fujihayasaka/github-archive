# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class RepositoryPackageReleases < ArrayWrapper
      attr_accessor :has_next_page, :has_previous_page, :start_cursor, :end_cursor, :total_count

      def paged_nodes
        # Use nodes as-is since dependency graph returns things already paged
        nodes
      end

      def sliced_nodes
        # Use nodes as-is since dependency graph returns things already sliced
        nodes
      end
    end
  end
end
