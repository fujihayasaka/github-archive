# typed: true
# frozen_string_literal: true

module Stafftools
  module Explore
    class ShowcaseComponent < Stafftools::Explore::BaseComponent
      def initialize(showcase:, context: Stafftools::Explore::BaseComponent::DEFAULT_CONTEXT)
        super(context: context)
        @showcase = showcase
      end

      private

      attr_reader :showcase

      def render?
        return false unless GitHub.showcase_enabled?

        showcase.present?
      end

      def items
        @items ||= showcase.items.includes(:item)
      end

      def edit_path
        if stafftools?
          edit_stafftools_showcase_collection_path(showcase)
        else
          edit_biztools_showcase_collection_path(showcase)
        end
      end

      def creator_path
        if stafftools?
          stafftools_user_path(showcase.owner)
        else
          biztools_user_path(showcase.owner)
        end
      end

      def edit_item_path(item)
        if stafftools?
          edit_stafftools_showcase_collection_showcase_item_path(showcase, item)
        else
          edit_biztools_showcase_collection_showcase_item_path(showcase, item)
        end
      end

      def delete_item_path(item)
        if stafftools?
          stafftools_showcase_collection_showcase_item_path(showcase, item)
        else
          biztools_showcase_collection_showcase_item_path(showcase, item)
        end
      end
    end
  end
end
