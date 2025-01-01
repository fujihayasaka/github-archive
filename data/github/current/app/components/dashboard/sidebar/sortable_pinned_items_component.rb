# typed: false
# frozen_string_literal: true

module Dashboard
  module Sidebar
    class SortablePinnedItemsComponent < ApplicationComponent
      # Renders an ordered list of items that can be reordered when used with `pinned-item-reordering.ts`

      renders_many :items, -> (item_id:, item_type:, **args, &block) do
        render Dashboard::Sidebar::SortableItemComponent.new(
          item_id: item_id,
          item_type: item_type,
          sortable: sortable,
          **args
        ).with_content(block&.call)
      end

      # @param user_id - The ID of the user whose items are being reordered.
      # @param sortable_path - The path where the new item order payload should be sent to be saved.
      # @param sortable _[Optional] - A boolean to enable sortable behavior. Gets passed down to `:items` slot. Defaults to `true`.
      # @param **system_arguments _[Optional]_ - A Hash of [system arguments](https://primer.style/view-components/system-arguments) to be placed the outermost element.
      def initialize(
        user_id:,
        sortable_path:,
        sortable: true,
        **system_arguments
      )
        @sortable = sortable
        @sortable_path = sortable_path
        @system_arguments = system_arguments

        @system_arguments[:classes] = class_names(
          system_arguments[:classes],
          "js-pinned-items-reorder-container" => sortable
        )
      end

      private

      attr_reader :user_id, :sortable, :sortable_path, :system_arguments
    end
  end
end
