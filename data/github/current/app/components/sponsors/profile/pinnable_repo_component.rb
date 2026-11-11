# typed: true
# frozen_string_literal: true

module Sponsors
  module Profile
    class PinnableRepoComponent < ApplicationComponent
      include UsersHelper

      def initialize(
        pinnable_item:,
        is_first_item:,
        is_pinned:,
        pinned_items_remaining:,
        this_user:,
        pagination_url: nil
      )
        @pinnable_item = pinnable_item
        @is_first_item = is_first_item
        @is_pinned = is_pinned
        @pagination_url = pagination_url
        @this_user = this_user
        @pinned_items_remaining = pinned_items_remaining
      end

      private

      attr_reader :pinnable_item, :pinned_items_remaining, :is_pinned, :is_first_item, :this_user

      # Returns calculated title for the pinnable item depending on its owner
      def title
        if pinnable_item.owner.display_login == this_user.display_login
          pinnable_item.name
        else
          pinnable_item.name_with_display_owner
        end
      end

      # Returns calculated classes for the pinnable item <li> element
      def li_classes
        class_names(
          pinnable_item.fork? ? "fork" : "source",
          "no-description" => pinnable_item.description.blank?
        )
      end

      # Returns calculated attributes for the pinnable item <input> checkbox element
      def input_attributes
        class_names(
          "checked" => is_pinned,
          "disabled" => pinned_items_remaining < 1 && !is_pinned,
          'data-targets="remote-pagination.focusMarkers"' => is_first_item
        )
      end

      def octicon_name
        "repo"
      end

      def octicon_label
        "public repo"
      end
    end
  end
end
