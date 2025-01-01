# typed: strict
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class ProjectV2ItemsElasticsearchQuery < ConnectionWrappers::Base
      include GitHub::Memoizer
      extend T::Sig

      sig { returns(MemexProject) }
      attr_reader :memex_project

      sig do
        params(
          memex_project: MemexProject,
          arguments: T::Hash[T.untyped, T.untyped],
          context: GraphQL::Query::Context,
          after: T.nilable(String),
          before: T.nilable(String),
          first: T.nilable(Integer),
          last: T.nilable(Integer),
          kwargs: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(
        memex_project:,
        arguments:,
        context:,
        after:,
        before:,
        first:,
        last:,
        **kwargs
      )
        super(
          nil,
          arguments:,
          after:,
          first:,
          before:,
          last:,
          context:,
          **kwargs
        )

        @memex_project = T.let(memex_project, MemexProject)
        @backend = T.let(Helpers::Projects::ElasticsearchBackend.new(
          viewer: context[:viewer],
          cap_filter: context[:cap_filter]
        ), Helpers::Projects::ElasticsearchBackend)
      end

      sig { returns(T::Array[MemexProjectItem]) }
      def edge_nodes
        backend_project_items_response.items
      end

      sig { returns(T::Array[MemexProjectItem]) }
      def nodes
        edge_nodes
      end

      sig { returns(PageInfo) }
      def page_info
        backend_project_items_response.page_info
      end

      sig { returns(Integer) }
      def total_count
        backend_project_items_response.total_count
      end

      sig { params(item: MemexProjectItem).returns(T.nilable(String)) }
      def cursor_for(item)
        item.cursor
      end

      private

      sig { returns(Helpers::Projects::ElasticsearchBackend) }
      attr_reader :backend

      sig { returns(Platform::Models::ProjectItemsPage) }
      memoize def backend_project_items_response
        backend.project_items(
          memex_project,
          after:,
          before:,
          first:,
          last:,
          order_by: arguments[:order_by][:direction]
        )
      rescue Search::Queries::CursorPagination::ParameterError => e
        raise Platform::Errors::ArgumentError, e.message.gsub(":", "")
      end

      sig { returns(T::Hash[T.nilable(Integer), Integer]) }
      memoize def index_for_item
        edge_nodes.each_with_index.reduce({}) do |acc, (i, index)|
          acc[i.id] = index
          acc
        end
      end
    end
  end
end
