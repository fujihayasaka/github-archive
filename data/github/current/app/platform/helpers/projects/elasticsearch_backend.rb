# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    module Projects
      # Consider this class as the bridge between the underlying Search::Queries::MemexProjectItemQuery class
      # and our GraphQL object model. This class knows how to take input from GraphQL, shape it
      # for MemexProjectItemQuery, get the response, and transform the response for GraphQL.
      class ElasticsearchBackend
        include Filterable

        # Wraps up the results along with the paging metadata for the #groups method.
        class GroupsResult < T::Struct
          const :page_info, ConnectionWrappers::PageInfo
          const :project_groups, T::Array[Models::ProjectGroup]
        end

        # Internal value object used to decode wrapped cursors from GraphQL consumers.
        # There is a mismatch here: GraphQL consumers require the view group ids to be globally unique across
        # projects and project views so we need to wrap it up with the view id as well.
        #
        # The underlying concern here is that mobile simply behaves differently than the dotcom web Memex
        # experience. For example: mobile is heavily reliant on saved view state while the web UI/UX allows
        # for much more dynamic and robust user control. This means our multiplayer and dirty-view scenarios
        # are more problematic on mobile than web. The initial PR adding this Elasticsearch functionality
        # is not meant to change the UI/UX or impact the current consumer experience but it is worth noting
        # that at some point it should be revisited to increase mobile usability.
        # For more info, see: https://github.com/github/github/pull/309709
        class UnwrappedViewGroupId < T::Struct
          const :view_id, Integer
          const :column_id, T.nilable(Integer)
          const :value, T.nilable(String)
        end

        private_constant :UnwrappedViewGroupId

        sig { returns(T.nilable(User)) }
        attr_reader :viewer

        sig { returns(T.nilable(::ConditionalAccess::Filter)) }
        attr_reader :cap_filter

        sig do
          params(
            viewer: T.nilable(User),
            cap_filter: T.nilable(::ConditionalAccess::Filter)
          ).void
        end
        def initialize(viewer:, cap_filter:)
          @viewer = T.let(viewer, T.nilable(User))
          @cap_filter = T.let(cap_filter, T.nilable(::ConditionalAccess::Filter))

          freeze
        end

        # When `order_by` parameter is set to `DESC` order, it will reverse the default order of items as they appear from
        #   top to bottom in an unsorted Memex table, this is to support GraphQL expected position ordering.
        #   For more details, See https://docs.github.com/en/graphql/reference/input-objects#projectv2itemorder
        sig do
          params(
            memex_project: MemexProject,
            first: T.nilable(Integer),
            last: T.nilable(Integer),
            after: T.nilable(String),
            before: T.nilable(String),
            order_by: T.nilable(String),
          ).returns(Models::ProjectItemsPage)
        end
        def project_items(memex_project, first: nil, last: nil, after: nil, before: nil, order_by: "ASC")
          raise Errors::ArgumentError, "Invalid OrderBy value" unless order_by_direction_valid?(order_by)

          memex_project_item_response = Search::Queries::MemexProjectItemQuery.graphql_query(
            project: memex_project,
            reverse_priority: order_by == "DESC",
            viewer:,
            cap_filter:,
            after:,
            before:,
            first:,
            last:,
          ).execute

          items = memex_project_item_response.models
          page_info = make_page_info(memex_project_item_response)
          total_count = memex_project_item_response.total

          Models::ProjectItemsPage.new(items:, page_info:, total_count:)
        end

        # The query argument is additive and will be appended to the view's existing filter value.
        sig do
          params(
            memex_project_view: MemexProjectView,
            view_group_id: String,
            first: T.nilable(Integer),
            after: T.nilable(String),
            query: String
          )
          .returns(T.any(Promise[Models::ProjectGroup], Promise[NilClass]))
        end
        def async_group(memex_project_view, view_group_id, first: nil, after: nil, query: "")
          # There is nothing we can do without a present ID.
          return Promise.resolve(nil) if view_group_id.blank?

          async_project_and_minimal_columns(memex_project_view).then do |project, group_by_column, sort_by_columns_and_directions|
            unwrapped_view_group_id = unwrap_and_decode_view_group_id(view_group_id)

            # Two "invalid view group ID" cases here to be aware of:
            # 1. We may find consumers passing in a view group ID for a different view, in which case
            #    we should return nil and not use it.
            # 2. If the memex view is configured to group by a different column but the passed in ID was meant
            #    for a different group by column then the view group ID is now invalid.
            next nil if unwrapped_view_group_id.view_id != memex_project_view.id
            next nil if unwrapped_view_group_id.column_id != group_by_column&.id

            group_value_filters = nil
            grouping_options = nil

            if unwrapped_view_group_id.column_id && unwrapped_view_group_id.value
              group_value_filters = [MemexProjectColumn::Interface::Queryable::FieldValueFilter.new(
                field_object_or_id: T.must(unwrapped_view_group_id.column_id),
                field_value: T.must(unwrapped_view_group_id.value),
              )]
            elsif unwrapped_view_group_id.column_id
              grouping_options = MemexProjectColumn::Interface::Groupable::Options.new(
                field_object_or_id: T.must(unwrapped_view_group_id.column_id),
                cursor: after,
              )
            end

            memex_project_item_response = Search::Queries::MemexProjectItemQuery.new(
              project:,
              viewer:,
              cap_filter:,
              sort: sort_by_to_es_values(sort_by_columns_and_directions),
              group_value_filters:,
              grouping_options:,
              first:,
              after:,
              query: derive_query(memex_project_view:, query:),
              remove_spam: true,
            ).execute

            group = make_precomputed_group(memex_project_view, group_by_column, unwrapped_view_group_id.value, view_group_id)
            items = memex_project_item_response.models

            view_items = items.map { |item| Models::ProjectViewItem.new(item:, sort_values: item.sort_values) }
            page_info = make_page_info(memex_project_item_response)
            total_count = memex_project_item_response.total

            Models::ProjectGroup.new(
              view: memex_project_view,
              group: Models::ProjectItemFieldGroup.new(
                group:,
                view: memex_project_view
              ),
              items: view_items,
              page_info:,
              total_count:
            )
          end
        end

        # The query argument is additive and will be appended to the view's existing filter value.
        sig do
          params(
            memex_project_view: MemexProjectView,
            first: T.nilable(Integer),
            after: T.nilable(String),
            items_per_group: T.nilable(Integer),
            query: String,
            item_ids: T.nilable(T::Array[Integer])
          )
          .returns(Promise[Platform::Helpers::Projects::ElasticsearchBackend::GroupsResult])
        end
        def async_groups(memex_project_view, first: nil, after: nil, items_per_group: nil, query: "", item_ids: nil)
          async_project_and_minimal_columns(memex_project_view).then do |project, group_by_column, sort_by_columns_and_directions|
            grouping_options = if group_by_column
              MemexProjectColumn::Interface::Groupable::Options.new(
                field_object_or_id: group_by_column.to_field,
                cursor: after,
                grouped_items_page_size: items_per_group,
                groups_page_size: first
              )
            end

            memex_project_item_response = Search::Queries::MemexProjectItemQuery.new(
              project:,
              viewer:,
              cap_filter:,
              sort: sort_by_to_es_values(sort_by_columns_and_directions),
              grouping_options:,
              first: items_per_group,
              after:,
              query: derive_query(memex_project_view:, query:),
              remove_spam: true,
              item_ids:,
            ).execute

            items = memex_project_item_response.models

            project_groups =
              if memex_project_item_response.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
                grouped_es_response_to_models(memex_project_view, memex_project_item_response, items, group_by_column)
              else
                ungrouped_es_response_to_models(memex_project_view, memex_project_item_response, items)
              end

            GroupsResult.new(
              page_info: make_page_info_for_groups(memex_project_item_response),
              project_groups:
            )
          end
        end

        private

        sig { params(order_by: T.nilable(String)).returns(T::Boolean) }
        def order_by_direction_valid?(order_by)
          return true unless order_by
          Platform::Enums::OrderDirection.graphql_values.include?(order_by)
        end

        sig do
          params(
            memex_project_view: MemexProjectView,
            group_by_column: T.nilable(MemexProjectColumn),
            value: T.nilable(String),
            view_group_id: String
          ).returns(MemexProject::PrecomputedGroup)
        end
        def make_precomputed_group(memex_project_view, group_by_column, value, view_group_id)
          # We do not require a group by column to create a PrecomputedGroup, but when we have one
          # we can delegate value and title derivation to the Field base & subclasses.
          field = group_by_column&.to_field

          MemexProject::PrecomputedGroup.new(
            view: memex_project_view,
            column: group_by_column,
            title: field&.graphql_title(value) || "",
            value: field&.graphql_value(value),
            view_group_id:
          )
        end

        sig { params(memex_project_view: MemexProjectView).returns(Promise[T.untyped]) }
        def async_project_and_minimal_columns(memex_project_view)
          promises = [
            memex_project_view.async_memex_project,
            memex_project_view.async_group_by_column,
            memex_project_view.async_sort_by_columns
          ]

          ::Promise.all(promises)
        end

        sig do
          params(
            memex_project_view: MemexProjectView,
            group_by_column: T.nilable(MemexProjectColumn),
            group: MemexProjectColumn::Interface::Groupable::Group
          ).returns(MemexProject::PrecomputedGroup)
        end
        def es_group_to_precomputed_group(memex_project_view, group_by_column, group)
          value = group.group_value
          view_group_id = wrap_es_group_id(memex_project_view.id, group.group_id)

          make_precomputed_group(memex_project_view, group_by_column, value, view_group_id)
        end

        sig do
          params(
            memex_project_view: MemexProjectView,
            memex_project_item_response: Search::Responses::GroupedMemexProjectItemResponse,
            items: T::Array[MemexProjectItem],
            group_by_column: T.nilable(MemexProjectColumn)
          ).returns(T::Array[Models::ProjectGroup])
        end
        def grouped_es_response_to_models(memex_project_view, memex_project_item_response, items, group_by_column)
          items_by_id = items.index_by(&:id)

          memex_project_item_response.primary_groups.nodes.map do |internal_group|
            group = es_group_to_precomputed_group(memex_project_view, group_by_column, internal_group)

            internal_grouped_items = memex_project_item_response.grouped_items.find { |g| g.group_id == internal_group.group_id }

            view_items = (internal_grouped_items&.paginated_items || []).filter_map do |item_es_result|
              id = item_es_result.dig("_source", "database_id")
              next unless (item = items_by_id[id]).present?
              Models::ProjectViewItem.new(item:, sort_values: item.sort_values)
            end

            page_info = ConnectionWrappers::PageInfo.new(
              has_next_page: !!(internal_grouped_items&.has_next_page),
              has_previous_page: !!(internal_grouped_items&.has_previous_page),
              start_cursor: internal_grouped_items&.start_cursor,
              end_cursor: internal_grouped_items&.end_cursor
            )
            total_count = internal_group.total_count.value

            Models::ProjectGroup.new(
              view: memex_project_view,
              group: Models::ProjectItemFieldGroup.new(
                group:,
                view: memex_project_view
              ),
              items: view_items,
              page_info:,
              total_count:
            )
          end
        end

        sig do
          params(
            memex_project_view: MemexProjectView,
            memex_project_item_response: Search::Responses::MemexProjectItemResponse,
            items: T::Array[MemexProjectItem]
          ).returns(T::Array[Platform::Models::ProjectGroup])
        end
        def ungrouped_es_response_to_models(memex_project_view, memex_project_item_response, items)
          return [] if items.empty?
          group = MemexProject::PrecomputedGroup.new(
            view: memex_project_view,
            view_group_id: wrap_es_group_id(memex_project_view.id, ungrouped_es_view_group_id)
          )

          view_items = items.map { |item| Models::ProjectViewItem.new(item:, sort_values: item.sort_values) }
          page_info = make_page_info(memex_project_item_response)
          total_count = memex_project_item_response.total

          [
            Models::ProjectGroup.new(
              view: memex_project_view,
              group: Models::ProjectItemFieldGroup.new(
                group:,
                view: memex_project_view
              ),
              items: view_items,
              page_info:,
              total_count:
            )
          ]
        end

        sig { params(columns_and_directions: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])).returns(T::Array[T.untyped]) }
        def sort_by_to_es_values(columns_and_directions)
          return [] unless columns_and_directions.present?

          columns_and_directions.filter_map do |sort_by|
            field = sort_by[:column]&.to_field
            next if field.nil? || field.class.disabled?
            field.sort_fragment(direction: sort_by[:direction])
          end
        end

        sig do
          params(memex_project_item_response: T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse))
          .returns(ConnectionWrappers::PageInfo)
        end
        def make_page_info_for_groups(memex_project_item_response)
          if memex_project_item_response.grouped?
            make_page_info(memex_project_item_response)
          else
            make_blank_page_info
          end
        end

        sig { returns(Platform::ConnectionWrappers::PageInfo) }
        def make_blank_page_info
          ConnectionWrappers::PageInfo.new(
            has_next_page: false,
            has_previous_page: false,
            start_cursor: nil,
            end_cursor: nil
          )
        end

        sig do
          params(memex_project_item_response: T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse))
          .returns(Platform::ConnectionWrappers::PageInfo)
        end
        def make_page_info(memex_project_item_response)
          ConnectionWrappers::PageInfo.new(
            has_next_page: memex_project_item_response.has_next_page,
            has_previous_page: memex_project_item_response.has_previous_page,
            start_cursor: memex_project_item_response.start_cursor,
            end_cursor: memex_project_item_response.end_cursor
          )
        end

        sig { params(view_id: T.nilable(Integer), group_id: String).returns(String) }
        def wrap_es_group_id(view_id, group_id)
          ConnectionWrappers::CursorGenerator.generate_cursor([view_id, group_id], version: :v2)
        end

        sig { params(id: String).returns(UnwrappedViewGroupId) }
        def unwrap_and_decode_view_group_id(id)
          # We double-wrapped the cursor to include the view id so first unwrap it from the view_id
          view_id, elasticsearch_id = ConnectionWrappers::CursorGenerator.resolve_cursor(id)

          # Then we can decode the underlying elasticsearch id for the actual values.
          column_id, value = ConnectionWrappers::CursorGenerator.resolve_cursor(elasticsearch_id)

          UnwrappedViewGroupId.new(view_id:, column_id:, value:)
        end

        # When we do not have a grouped view we should still return a "virtual group". We can derive our own
        # stand-in for this in a compatible manner.
        sig { returns(String) }
        def ungrouped_es_view_group_id
          ConnectionWrappers::CursorGenerator.generate_cursor([nil, nil], version: :v2)
        end
      end
    end
  end
end
