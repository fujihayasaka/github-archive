# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    module Projects
      # This is the legacy, non-paginated implementation. This is subject to be removed in the future once
      # all clients have been migrated to the new paginated implementation.
      class InMemoryBackend
        extend T::Sig
        include Filterable

        sig { returns(User) }
        attr_reader :viewer

        sig { params(viewer: User).void }
        def initialize(viewer:)
          @viewer = viewer

          freeze
        end

        # The query argument is additive and will be appended to the view's existing filter value.
        sig { params(memex_project_view: MemexProjectView, view_group_id: String, query: String).returns(Promise[Models::ProjectGroup]) }
        def async_group(memex_project_view, view_group_id, query: "")
          async_groups(memex_project_view, query:).then do |project_groups|
            project_groups.find { |project_group| project_group.view_group_id == view_group_id }
          end
        end

        # The new paginated implementation. The query argument is additive and will be appended to the
        # view's existing filter value.
        sig { params(memex_project_view: MemexProjectView, query: String).returns(Promise[T::Array[Models::ProjectGroup]]) }
        def async_groups(memex_project_view, query: "")
          async_grouped_view_items(memex_project_view, query:).then do |ranked_item_promises|
            Promise.all(ranked_item_promises).then do |project_grouped_view_items|
              # Re-shape Models::ProjectGroupedViewItem objects as Models::ProjectGroup objects.
              project_groups = project_grouped_view_items.map do |project_grouped_view_item|
                Models::ProjectGroup.new(
                  view: project_grouped_view_item.view,
                  group: project_grouped_view_item.group,
                  items: project_grouped_view_item.view_items
                )
              end

              ArrayWrapper.new(project_groups)
            end
          end
        end

        # This is the legacy non-paginated implementation.
        sig { params(memex_project_view: MemexProjectView, query: String).returns(Promise[T::Array[Models::ProjectGroupedViewItems]]) }
        def async_grouped_view_items(memex_project_view, query: "")
          async_group_ranked_search(memex_project_view, query:).then do |grs|
            grs.async_execute.then do |ranked_items|
              ranked_items.map do |group, items|
                async_filter_visible_grouped_items(memex_project_view, items).then do |visible_items|
                  project_items = visible_items.map { |i| i[:item] }
                  GitHub::PrefillAssociations.prefill_batch_method(project_items, :is_content_spammy?, viewer)
                  nonspammy_visible_items = visible_items.reject { |ranked_item| ranked_item[:item].is_content_spammy?(viewer) }
                  Models::ProjectGroupedViewItems.wrap(nonspammy_visible_items, group: group, view: memex_project_view)
                end
              end
            end
          end
        end

        # This is the legacy non-paginated implementation for fetching all non-archived Memex Project Items
        sig { params(memex_project: MemexProject, order_by: Inputs::ProjectV2ItemOrder).returns(Promise[T::Array[MemexProjectItem]]) }
        def async_project_items(memex_project:, order_by:)
          # prioritized_scope returns all non_archived items, ordered by priority, with no 1200 item limit applied.

          items = memex_project.prioritized_scope(:memex_project_items)
          GitHub::PrefillAssociations.prefill_batch_method(items, :is_content_spammy?, viewer)
          filtered = items.reject { |n| n.is_content_spammy?(viewer) }
          Promise.resolve(Helpers::ProjectV2.order_objects(filtered, order_by, omit_ordering: true))
        end


        private

        sig { params(memex_project_view: MemexProjectView, items: T::Array[T::Hash[Symbol, T.untyped]]).returns(Promise[T::Array[T::Hash[Symbol, T.untyped]]]) }
        def async_filter_visible_grouped_items(memex_project_view, items)
          if memex_project_view.filter.present?
            Promise.all(items.map { |item| item[:item].async_readable_by_viewer?(viewer) }).then do |readable_by_viewer_results|
              items.select.with_index { |_item, index| readable_by_viewer_results[index] }
            end
          else
            Promise.resolve(items)
          end
        end

        # Internal: This method performs the actual in-memory filtering, sorting, and grouping of the project's
        # items using the GroupedRankedSearch class.
        sig { params(memex_project_view: MemexProjectView, query: String).returns(Promise[MemexProjectView::GroupedRankedSearch]) }
        def async_group_ranked_search(memex_project_view, query: "")
          memex_project_view.async_memex_project.then do |memex|
            promises = [
              memex.async_memex_project_columns,
              memex.async_prioritized_scope(:memex_project_items),
              memex_project_view.async_group_by_column,
              memex_project_view.async_sort_by_column
            ]

            Promise.all(promises).then do |columns, items, group_by, sort_by|
              MemexProjectView::GroupedRankedSearch.new(
                memex:,
                view: memex_project_view,
                filter: derive_query(memex_project_view:, query:),
                columns:,
                items:,
                viewer:,
                group_by:,
                sort_by:,
                visible_fields: memex_project_view.visible_fields,
                use_redactor: false
              )
            end
          end
        end
      end
    end
  end
end
