# typed: true
# frozen_string_literal: true

module Site
  module Header
    class ContextRegionComponent < ApplicationComponent
      MAX_PARENT_SIZE_COMPACT = 1

      ITEM_ACCESS_TYPE_ICON_MAPPING = {
        default: "",
        public: "",
        internal: "",
        private: "",
      }

      attr_reader :context_items, :current_path

      def initialize(context_items: [], current_path: nil)
        @context_items = context_items
        @current_path = current_path
      end

      def path(item)
        return "#" unless item.has_path?

        if item.path
          item.path
        else
          T.unsafe(self).send(item.path_name, *item.path_args)
        end
      end

      # All context items before the final available parent
      def context_item_compact_parents
        parent_items = context_items[0...-1]
        parent_items[0...MAX_PARENT_SIZE_COMPACT]
      end

      # If there's overflow, the final available parent is treated as overflow
      def context_item_compact_parent_overflow
        parent_items = context_items[0...-1]
        parent_items[MAX_PARENT_SIZE_COMPACT]
      end

      def compact_longer_chain?
        context_items.length > MAX_PARENT_SIZE_COMPACT + 2
      end

      def context_item_full_parents
        context_items[0...-1]
      end

      def context_item_leaf
        context_items.last
      end

      def page_context
        context_items.map(&:label).join(" / ")
      end
    end
  end
end
