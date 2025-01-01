# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2View < Platform::Objects::Base
      model_name "MemexProjectView"
      description "A view within a ProjectV2."

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      visibility :public, environments: [:dotcom, :enterprise]

      PREFIX = Helpers::ProjectV2::Prefix.new("PVTV", :opvtv, :upvtv)
      implements_node templates: [
        [PREFIX.org, :owner_id, :project_id, :id],
        [PREFIX.user, :owner_id, :project_id, :id],
        ],
        as: PREFIX.to_s,
        ready_date: "1970-01-01" do |project_view|
        project_view.async_memex_project.then do |project|
          prefix = case project.owner_type
          when "Organization"
            PREFIX.org
          when "User"
            PREFIX.user
          else
            raise Platform::Errors::Internal, "Unexpected project owner: #{project.owner_type.inspect}"
          end
          {
            prefix: prefix,
            owner_id: project.owner_id,
            project_id: project.id,
            id: project_view.id
          }
        end
      end

      minimum_accepted_scopes ["read:project"]

      field :project, Platform::Objects::ProjectV2, description: "The project that contains this view.", null: false, method: :async_memex_project

      DeprecationNotice = {
        start_date: Date.new(2024, 10, 1),
        reason: "`databaseId` will be removed because it does not support 64-bit signed integer identifiers.",
        superseded_by: "Use `fullDatabaseId` instead.",
        owner: "dewski",
      }

      database_id_field(deprecated: DeprecationNotice)

      full_database_id_field

      created_at_field

      updated_at_field

      field :name, String, "The project view's name.", null: false

      field :number, Integer, "The project view's number.", null: false

      field :filter, String, "The project view's filter.", null: true

      field :layout, Platform::Enums::ProjectV2ViewLayout, "The project view's layout.", null: false
      def layout
        if Platform::Enums::ProjectV2ViewLayout.graphql_values.include? @object.layout.upcase
          return @object.layout
        end
        raise Platform::Errors::Internal, "Unexpected layout: #{@object.layout}"
      end

      field :visible_fields,
            Connections.define(ProjectV2Field),
            "The view's visible fields.",
            connection: true,
            null: true,
            numeric_pagination_enabled: true,
            deprecated: {
              start_date: Date.new(2022, 9, 11),
              reason: "The `ProjectV2View#visibleFields` API is deprecated in favour of the more capable `ProjectV2View#fields` API.",
              superseded_by: "Check out the `ProjectV2View#fields` API as an example for the more capable alternative.",
              owner: "mattruggio",
            } do
        argument :order_by,
                 Inputs::ProjectV2FieldOrder,
                 "Ordering options for the project v2 fields returned from the connection.",
                 required: false,
                 default_value: { field: "position", direction: "ASC" }
      end
      def visible_fields(order_by:)
        retrieve_field_connection_for(:visible_fields, order_by: order_by)
      end

      field :fields,
            Connections.define(Unions::ProjectV2FieldConfiguration),
            "The view's visible fields.",
            connection: true,
            null: true,
            numeric_pagination_enabled: true do
        argument :order_by,
                 Inputs::ProjectV2FieldOrder,
                 "Ordering options for the project v2 fields returned from the connection.",
                 required: false,
                 default_value: { field: "position", direction: "ASC" }
      end
      def fields(order_by:)
        retrieve_field_connection_for(:visible_fields, order_by: order_by)
      end

      field :group_by,
            Connections.define(ProjectV2Field),
            "The view's group-by field.",
            connection: true,
            null: true,
            numeric_pagination_enabled: true,
            deprecated: {
              start_date: Date.new(2022, 10, 05),
              reason: "The `ProjectV2View#order_by` API is deprecated in favour of the more capable `ProjectV2View#group_by_field` API.",
              superseded_by: "Check out the `ProjectV2View#group_by_fields` API as an example for the more capable alternative.",
              owner: "alcere",
            } do
        argument :order_by,
                 Inputs::ProjectV2FieldOrder,
                 "Ordering options for the project v2 fields returned from the connection.",
                 required: false,
                 default_value: { field: "position", direction: "ASC" }
      end
      def group_by(order_by:)
        retrieve_field_connection_for(:group_by, order_by: order_by)
      end

      field :group_by_fields,
            Connections.define(Unions::ProjectV2FieldConfiguration),
            "The view's group-by field.",
            connection: true,
            null: true,
            numeric_pagination_enabled: true do
        argument :order_by,
                 Inputs::ProjectV2FieldOrder,
                 "Ordering options for the project v2 fields returned from the connection.",
                 required: false,
                 default_value: { field: "position", direction: "ASC" }
      end
      def group_by_fields(order_by:)
        retrieve_field_connection_for(:group_by, order_by: order_by)
      end

      field :vertical_group_by,
            Connections.define(ProjectV2Field),
            "The view's vertical-group-by field.",
            connection: true, null: true,
            numeric_pagination_enabled: true,
            deprecated: {
              start_date: Date.new(2022, 10, 17),
              reason: "The `ProjectV2View#vertical_group_by` API is deprecated in favour of the more capable `ProjectV2View#vertical_group_by_fields` API.",
              superseded_by: "Check out the `ProjectV2View#vertical_group_by_fields` API as an example for the more capable alternative.",
              owner: "traumverloren",
            } do
        argument :order_by,
                 Inputs::ProjectV2FieldOrder,
                 "Ordering options for the project v2 fields returned from the connection.",
                 required: false,
                 default_value: { field: "position", direction: "ASC" }
      end
      def vertical_group_by(order_by:)
        # There is a special case when a view is set to board layout but has never explicitly been updated
        # to include a specific vertical group by field.  In this case we want to return the Status column.
        if @object.board_layout? && @object.vertical_group_by.empty?
          @object.memex_project.async_memex_project_columns.then do
            status_column = @object.memex_project.status_column

            ArrayWrapper.new([status_column])
          end
        else
          retrieve_field_connection_for(:vertical_group_by, order_by: order_by)
        end
      end

      field :vertical_group_by_fields, Connections.define(Unions::ProjectV2FieldConfiguration), "The view's vertical-group-by field.", connection: true, null: true, numeric_pagination_enabled: true do
        argument :order_by, Inputs::ProjectV2FieldOrder, "Ordering options for the project v2 fields returned from the connection.", required: false, default_value: { field: "position", direction: "ASC" }
      end
      def vertical_group_by_fields(order_by:)
        # There is a special case when a view is set to board layout but has never explicitly been updated
        # to include a specific vertical group by field.  In this case we want to return the Status column.
        if @object.board_layout? && @object.vertical_group_by.empty?
          @object.memex_project.async_memex_project_columns.then do
            status_column = @object.memex_project.status_column

            ArrayWrapper.new([status_column])
          end
        else
          retrieve_field_connection_for(:vertical_group_by, order_by: order_by)
        end
      end

      def retrieve_field_connection_for(field_name, order_by: nil)
        field_ids = @object.send(field_name)
        @object.async_memex_project.then do |project|
          project.async_owner.then do |owner|
            Loaders::MemexProjectColumn.load_all(
              project,
              owner,
              @context[:viewer],
              ids: field_ids
            ).then { |fields| Helpers::ProjectV2.order_objects(fields, order_by) }
          end
        end
      end

      field :items, Connections.define(Objects::ProjectV2Item), "The view's filtered items.", connection: true, null: false, numeric_pagination_enabled: true, required_capabilities: [:mobile_only_schema_mask] do
        argument :order_by, Inputs::ProjectV2ItemOrder, "Ordering options for project v2 items returned from the connection.", required: false, default_value: { field: "position", direction: "ASC" }
      end
      def items(order_by:)
        @object.async_memex_project.then do |memex|
          filter = @object.filter

          # The methods (async_)prioritized_scope will filter archived items out of the results.
          async_items = if filter.blank?
            Promise.resolve(memex.prioritized_scope(:memex_project_items))
          else
            memex.async_prioritized_scope(:memex_project_items).then do |items|
              memex.async_filter_items(
                memex_items: items,
                filter: filter,
                viewer: @context[:viewer],
                visible_fields: @object.visible_fields
              ).then do |filtered_items|
                Promise.all(
                  filtered_items.map { |item| item.async_readable_by_viewer?(@context[:viewer]) }
                ).then do |readable_by_viewer_results|
                  Helpers::ProjectV2.order_objects(
                    filtered_items.select.with_index { |_item, index| readable_by_viewer_results[index] },
                    order_by,
                    omit_ordering: true
                  )
                end
              end
            end
          end

          async_items.then { |items| ArrayWrapper.new(remove_spammy_items(items:)) }
        end
      end

      # Note - this is a special field that controls the sort by arrangement of the view, and therefore doesn't warrant an orderBy argument
      field :sort_by,
            Connections.define(Platform::Objects::ProjectV2SortBy),
            "The view's sort-by config.", connection: true,
            null: true,
            numeric_pagination_enabled: true,
            deprecated: {
              start_date: Date.new(2022, 10, 17),
              reason: "The `ProjectV2View#sort_by` API is deprecated in favour of the more capable `ProjectV2View#sort_by_fields` API.",
              superseded_by: "Check out the `ProjectV2View#sort_by_fields` API as an example for the more capable alternative.",
              owner: "traumverloren",
            }
      def sort_by
        results = T.let([], T::Array[T.untyped])
        @object.sort_by.each do |sort_by_field|
          next if sort_by_field.blank? || sort_by_field.size < 2

          field, sort_direction = sort_by_field

          direction = case sort_direction.downcase
          when "asc"
            "ASC"
          when "desc"
            "DESC"
          else
            nil
          end

          results.push({ field: field, direction: direction }) if field.is_a?(Integer) && direction.present?
        end
        @object.async_memex_project.then do |project|
          project.async_memex_project_columns.then do |columns|
            results = results.map do |r|
              field = columns.find { |c| c.id == r[:field] }
              r[:field] = Platform::Helpers::ProjectV2Field.coerce(field)
              r
            end
            ArrayWrapper.new(results)
          end
        end
      end

      # Note - this is a special field that controls the sort by arrangement of the view, and therefore doesn't warrant an orderBy argument
      field :sort_by_fields, Connections.define(Platform::Objects::ProjectV2SortByField), "The view's sort-by config.", connection: true, null: true, numeric_pagination_enabled: true
      def sort_by_fields
        results = T.let([], T::Array[T.untyped])
        @object.sort_by.each do |sort_by_field|
          next if sort_by_field.blank? || sort_by_field.size < 2

          field, sort_direction = sort_by_field

          direction = case sort_direction.downcase
          when "asc"
            "ASC"
          when "desc"
            "DESC"
          else
            nil
          end

          results.push({ field: field, direction: direction }) if field.is_a?(Integer) && direction.present?
        end
        @object.async_memex_project.then do |project|
          project.async_memex_project_columns.then do |columns|
            results = results.map do |r|
              field = columns.find { |c| c.id == r[:field] }
              r[:field] = Platform::Helpers::ProjectV2Field.coerce(field)
              r
            end
            ArrayWrapper.new(results)
          end
        end
      end

      field :group,
        Objects::ProjectV2Group,
        description: "A single group based on the view's group by.",
        required_capabilities: [:mobile_only_schema_mask],
        extras: %i[lookahead],
        null: true do
        argument :view_group_id,
          String,
          "Underlying group ID to identify the group within a view.",
          required: false,
          default_value: nil

        argument :query,
          String,
          "If provided, will use to filter view items over the view's saved filter value. If omitted then the view's filter value will be used.",
          required: false
      end

      def group(**arguments)
        view_group_id = arguments[:view_group_id]
        lookahead = arguments[:lookahead]
        query = arguments[:query].to_s # This value will be appended on to the view's saved filter value.

        async_use_elasticsearch?.then do |use_elasticsearch|
          if use_elasticsearch
            item_arguments = lookahead.selection(:items).arguments || {}
            first = item_arguments[:first]
            after = item_arguments[:after]

            elasticsearch_backend.async_group(object, view_group_id, first:, after:, query:)
          else
            in_memory_backend.async_group(object, view_group_id, query:)
          end
        end
      end

      field :groups,
        Connections::ProjectV2Group,
        required_capabilities: [:mobile_only_schema_mask],
        null: false,
        connection: false,
        extras: %i[lookahead],
        description: "Pageable groups of items." do
        has_connection_arguments

        argument :query,
          String,
          "If provided, will use to filter view items over the view's saved filter value. If omitted then the view's filter value will be used.",
          required: false

        argument :with_item_database_ids,
          [Platform::Scalars::BigInt],
          "Filter groups to only those that include items with the given database IDs. Does not return empty groups by default.",
          required: false,
          as: :item_ids
      end

      def groups(**arguments)
        async_use_elasticsearch?.then do |use_elasticsearch|
          item_arguments = lookahead_item_arguments(arguments[:lookahead])

          arguments[:memex_project_view] = object
          arguments[:items_per_group] = item_arguments[:first] || item_arguments[:last] || 1

          query_class = if use_elasticsearch
            ConnectionWrappers::ProjectV2GroupElasticsearchQuery
          else
            ConnectionWrappers::ProjectV2GroupQuery
          end

          query_class.new(
            nil,
            first: arguments[:first],
            last: arguments[:last],
            after: arguments[:after],
            before: arguments[:before],
            arguments:,
            context:,
          )
        end
      end

      field :grouped_items,
        [Objects::ProjectV2GroupedViewItems],
        null: false,
        description: "The grouped view items.",
        required_capabilities: [:mobile_only_schema_mask]

      def grouped_items
        in_memory_backend.async_grouped_view_items(object, query: object.filter.to_s)
      end

      private

      def async_use_elasticsearch?
        Helpers::Projects::Backend.async_use_elasticsearch?(
          memex_project_or_view: object,
        )
      end

      def in_memory_backend
        Helpers::Projects::InMemoryBackend.new(viewer: context[:viewer])
      end

      def elasticsearch_backend
        Helpers::Projects::ElasticsearchBackend.new(
          viewer: context[:viewer],
          cap_filter: context[:cap_filter]
        )
      end

      def remove_spammy_items(items:)
        viewer = @context[:viewer]
        GitHub::PrefillAssociations.prefill_batch_method(items, :is_content_spammy?, viewer)
        items.reject { |n| n.is_content_spammy?(viewer) }
      end

      def lookahead_item_arguments(lookahead)
        begin
          if lookahead.selection(:nodes).selects?(:items)
            lookahead.selection(:nodes).selection(:items).arguments
          elsif lookahead.selection(:edges).selection(:node).selects?(:items)
            lookahead.selection(:edges).selection(:node).selection(:items).arguments
          end
        end || {}
      end
    end
  end
end
