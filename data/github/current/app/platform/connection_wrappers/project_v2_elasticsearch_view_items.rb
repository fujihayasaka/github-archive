# typed: strict
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    # This connection wrapper is a pass-thru for the resulting response from
    # Elasticsearch (via MemexProjectItemQuery).
    class ProjectV2ElasticsearchViewItems < ConnectionWrappers::Base
      extend T::Sig

      sig { returns(Models::ProjectGroup) }
      attr_reader :items

      sig { params(items: Models::ProjectGroup, kwargs: T::Hash[Symbol, T.untyped]).void }
      def initialize(items, **kwargs)
        @items = items
        super(items, **kwargs)
      end

      sig { returns(Integer) }
      def total_count
        @items.total_count
      end

      sig { returns([]) }
      def edges
        []
      end

      sig { returns(T::Array[Models::ProjectViewItem]) }
      def edge_nodes
        @items.items
      end

      sig { returns(ConnectionWrappers::PageInfo) }
      def page_info
        @items.page_info
      end
    end
  end
end
