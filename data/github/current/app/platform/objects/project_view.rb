# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectView < Platform::Objects::Base
      model_name "MemexProjectView"
      description "A view within a Project."

      required_capabilities [:mobile_only_schema_mask]

      implements_node templates: [
        [:opnv, :org_id, :project_id, :project_view_id],
        [:upnv, :user_id, :project_id, :project_view_id],
        ],
        as: "PNV", ready_date: Platform::Interfaces::ProjectNextFieldCommon::PROJECT_NEXT_COHORT do |project_view|
        project_view.async_memex_project.then do |project|
          case project.owner_type
          when "Organization"
            {
              prefix: :opnv,
              org_id: project.owner_id,
              project_id: project.id,
              project_view_id: project_view.id
            }
          when "User"
            {
              prefix: :upnv,
              user_id: project.owner_id,
              project_id: project.id,
              project_view_id: project_view.id
            }
          else
            raise Platform::Errors::Internal, "Unexpected project owner: #{project.owner_type.inspect}"
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, project_view)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(permission.viewer, permission.oauth_app)

        project_view.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectNext", project)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, project_view)
        project_view.async_memex_project.then do |project|
          permission.typed_can_see?("ProjectNext", project)
        end
      end

      minimum_accepted_scopes ["read:org", "repo"]

      field :project, Platform::Objects::ProjectNext, description: "The project that contains this view.", null: false, method: :async_memex_project

      database_id_field

      created_at_field

      updated_at_field

      field :name, String, "The project view's name.", null: false

      field :number, Integer, "The project view's number.", null: false

      field :filter, String, "The project view's filter.", null: true

      field :layout, Platform::Enums::ProjectViewLayout, "The project view's layout.", null: false
      def layout
        if Platform::Enums::ProjectViewLayout.graphql_values.include? @object.layout.upcase
          return @object.layout
        end
        # Defaulting to Table layout in case the value returned is not yet supported by the API
        "table_layout"
      end

      field :visible_fields, [Integer], "The view's visible fields.", null: true

      field :group_by, [Integer], "The view's group-by field.", null: true

      field :vertical_group_by, [Integer], "The view's vertical-group-by field.", null: true

      field :sort_by, [Platform::Objects::SortBy], "The view's sort-by config.", null: true
      def sort_by
        result = []
        @object.sort_by.each do |sort_by_field|
          next if sort_by_field.nil? || sort_by_field.empty?
          field = sort_by_field[0]
          direction = if sort_by_field[1].downcase == "asc"
            "ASC"
          else
            (sort_by_field[1].downcase == "desc" ? "DESC" : nil)
          end

          next unless field.is_a?(Integer) && !direction.nil?
          result.push({ field: field, direction: direction })
        end
        result
      end

      field :items, Connections.define(Objects::ProjectNextItem), "The view's filtered items.", connection: true, null: false, numeric_pagination_enabled: true
      def items
        @object.async_memex_project.then do |memex|
          filter = @object.filter

          if filter.blank?
            memex.memex_project_items.not_archived
          else
            memex.async_memex_project_items.then do |items|
              items = items.reject(&:archived?).reverse

              memex.async_filter_items(
                memex_items: items,
                filter: filter,
                viewer: @context[:viewer],
                visible_fields: @object.visible_fields
              ).then do |filtered_items|
                Promise.all(
                  filtered_items.map { |item| item.async_readable_by_viewer?(@context[:viewer]) }
                ).then do |readable_by_viewer_results|
                  ArrayWrapper.new(filtered_items.select.with_index { |_item, index| readable_by_viewer_results[index] })
                end
              end
            end
          end
        end
      end

      field :grouped_items, [Objects::ProjectNextGroupedViewItems], "The grouped view items.", null: false
      def grouped_items
        async_group_ranked_search.then do |grs|
          grs.async_execute.then do |ranked_items|
            ranked_items.map do |group, items|
              async_filter_visible_grouped_items(items).then do |visible_items|
                Models::ProjectGroupedViewItems.wrap(
                  visible_items,
                  group: group,
                  view: @object,
                  v2: false
                )
              end
            end
          end
        end
      end

      def async_filter_visible_grouped_items(items)
        if @object.filter.present?
          Promise.all(items.map { |item| item[:item].async_readable_by_viewer?(@context[:viewer]) }).then do |readable_by_viewer_results|
            items = items.select.with_index { |_item, index| readable_by_viewer_results[index] }
          end
        else
          Promise.resolve(items)
        end
      end

      def async_group_ranked_search
        @object.async_memex_project.then do |memex|
          promises = [
            memex.async_memex_project_columns,
            memex.async_prioritized_scope(:memex_project_items),
            @object.async_group_by_column,
            @object.async_sort_by_column
          ]

          Promise.all(promises).then do |columns, items, group_by, sort_by|
            MemexProjectView::GroupedRankedSearch.new(
              memex: memex,
              view: @object,
              filter: @object.filter,
              columns: columns,
              items: items,
              viewer: @context[:viewer],
              group_by: group_by,
              sort_by: sort_by
            )
          end
        end
      end
    end
  end
end
