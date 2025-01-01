# typed: true
# frozen_string_literal: true

module Dashboard
  module Sidebar
    class SortableItemComponent < ApplicationComponent
      # @param item_id - The id of the item to be sorted.
      # @param item_type - The type of the item being reordered e.g. Repository, Issue, etc.
      # @param sortable _[Optional]_ - A boolean to enable sortable behavior. Defaults to `true`
      # @param **system_arguments _[Optional]_ - A Hash of [system arguments](https://primer.style/view-components/system-arguments) to be placed the outermost element
      def initialize(item_id:, item_type:, sortable: true, **system_arguments)
        @item_id = item_id
        @item_type = item_type
        @sortable = sortable

        system_arguments[:classes] = class_names(
          system_arguments[:classes],
          "dashboard-sidebar-sortable-item",
          "js-pinned-item-list-item sortable-button-item reorderable" => sortable
        )
        @system_arguments = system_arguments
      end

      attr_reader :item_id, :item_type, :sortable, :system_arguments
    end
  end
end
