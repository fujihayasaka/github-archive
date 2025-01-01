# typed: strict
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    # This connection wrapper connects to Elasticsearch via an ElasticsearchBackend instance.
    # It understands how to connect to a GraphQL connection field interface to the shape desired by
    # the ElasticsearchBackend interface.
    class ProjectV2GroupElasticsearchQuery < ConnectionWrappers::Base
      include GitHub::Memoizer

      sig { returns(Integer) }
      attr_reader :first

      sig { returns(T.nilable(String)) }
      attr_reader :after

      sig { returns(T.nilable(Integer)) }
      attr_reader :items_per_group

      sig { returns(String) }
      attr_reader :query

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :item_ids

      sig do
        params(
          items: T.untyped,
          first: Integer,
          arguments: T::Hash[T.untyped, T.untyped],
          context: GraphQL::Query::Context,
          last: T.nilable(Integer),
          after: T.nilable(String),
          before: T.nilable(String),
          kwargs: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(
        items,
        first:,
        arguments:,
        context:,
        last: nil,
        after: nil,
        before: nil,
        **kwargs
      )
        @first = T.let(first, Integer)
        @after = T.let(after, T.nilable(String))
        @items_per_group = T.let(arguments[:items_per_group], Integer)
        @query = T.let(arguments[:query].to_s, String) # This value will be appended on to the view's saved filter value.
        @item_ids = T.let(arguments[:item_ids], T.nilable(T::Array[Integer]))

        # The majority of the computation is delegated to Elasticsearch. The Helpers::Projects::ElasticsearchBackend
        # helps shape input/output to match GraphQL which in turn calls the Search::Queries::MemexProjectItemQuery
        # to craft the actual Elasticsearch query.
        @backend = T.let(Helpers::Projects::ElasticsearchBackend.new(
          viewer: context[:viewer],
          cap_filter: context[:cap_filter]
        ), Helpers::Projects::ElasticsearchBackend)

        super(
          items,
          arguments: arguments,
          first: first,
          last: last,
          after: after,
          before: before,
          context: context,
          **kwargs
        )
      end

      # Total count of groups is not currently supported by our Elasticsearch API.
      # Help indicate this via a hard-coded -1 return value for now, but more appropriately,
      # this field should simply be removed once it is deemed safe to change the schema.
      # Changing the schema was deemed out-of-scope for the project which introduced this connection wrapper:
      # https://github.com/github/github/pull/309709
      sig { returns(::Promise[Integer]) }
      def total_count
        ::Promise.resolve(-1)
      end

      sig { returns(::Promise[T::Array[Platform::Models::ProjectGroup]]) }
      def edge_nodes
        async_backend_groups_response.then do |groups_response|
          groups_response.project_groups
        end
      end

      sig { returns(::Promise[PageInfo]) }
      def page_info
        async_backend_groups_response.then do |groups_response|
          groups_response.page_info
        end
      end

      # We can hard-code this since this connection wrapper only uses Elasticsearch.
      sig { returns(T::Boolean) }
      def fulfilled_via_elasticsearch?
        true
      end

      sig { override.params(project_group: Models::ProjectGroup).returns(T.nilable(String)) }
      def cursor_for(project_group)
        view_id, elasticsearch_id = CursorGenerator.resolve_cursor(project_group.view_group_id)
        column_id, value = CursorGenerator.resolve_cursor(elasticsearch_id)
        CursorGenerator.generate_cursor({ "bucket" => value }, version: :v2)
      end

      private

      sig { returns(Helpers::Projects::ElasticsearchBackend) }
      attr_reader :backend

      # Memoize so we are ont making more than one call to Elasticsearch per connection wrapper exectuion.
      sig { returns(::Promise[Platform::Helpers::Projects::ElasticsearchBackend::GroupsResult]) }
      memoize def async_backend_groups_response
        backend.async_groups(
          arguments[:memex_project_view],
          first: capped_first,
          after:,
          items_per_group: capped_items_per_group,
          item_ids:,
          query:
        )
      end

      # Old mobile clients were previously requesting the first 25 groups and 25 items per group.
      # This will not work with the new backend's limitation of max 250 for groups * items.
      # These two artifical capping methods below are meant to allow older clients to be forward-compatible.
      # We can remove this once the client-side code has been updated to use the new page sizes.
      sig { returns(Integer) }
      def capped_first
        [first, MemexProjectColumn::Interface::Groupable::DEFAULT_GROUPS_PAGE_SIZE].min
      end

      sig { returns(Integer) }
      def capped_items_per_group
        # If we do not have any items_per_group passed in then treat it as 1 so the underlying Elasticsearch query
        # works and does not return an error saying that that the page size must be between 1 and 250.
        return 1 unless items_per_group

        [
          T.must(items_per_group),
          MemexProjectColumn::Interface::Groupable::DEFAULT_GROUPED_ITEMS_PAGE_SIZE
        ].min
      end
    end
  end
end
