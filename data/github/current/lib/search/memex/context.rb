# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    class Context
      extend T::Sig
      include GitHub::Memoizer

      class MemexProjectItemsScope < T::Enum
        enums do
          All = new(:all)
          Archived = new(:archived)
          Unarchived = new(:unarchived)
        end
      end

      # Options to allow overriding default Elasticsearch query construction.
      # For example, a post_filter or nested filter aggregation can omit redundant project and item scoping.
      class QueryOptions < T::Struct
        extend T::Sig
        prop :skip_project_scope, T::Boolean, default: false
        prop :skip_items_scope, T::Boolean, default: false
      end

      sig { returns(::MemexProject) }
      attr_reader :memex_project
      sig { returns(T.nilable(User)) }
      attr_reader :viewer
      sig { returns(MemexProjectItemsScope) }
      attr_reader :items_scope
      sig { returns(QueryOptions) }
      attr_reader :options

      sig do
        params(
          memex_project: ::MemexProject,
          viewer: T.nilable(User),
          items_scope: MemexProjectItemsScope,
          options: QueryOptions
        ).void
      end
      def initialize(memex_project:, viewer: nil, items_scope: MemexProjectItemsScope::Unarchived, options: QueryOptions.new)
        @memex_project = memex_project
        @viewer = viewer
        @items_scope = items_scope
        @options = options
      end

      sig { returns(T::Hash[T.any(Symbol, String), MemexProjectColumn::Field]) }
      memoize def field_by_query_slug
        memex_project
          .columns
          .each_with_object({}) do |column, result|
            next unless field = column.to_field
            result[field.query_slug] = field
          end
          .with_indifferent_access
      end
    end
  end
end
