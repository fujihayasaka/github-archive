# typed: true
# frozen_string_literal: true

module Dashboard
  module Favorites
    class PinnableFavoriteComponent < ApplicationComponent
      include UsersHelper
      include CachedOcticonHelper

      def initialize(
        pinnable_item:,
        is_first_item:,
        has_more_items:,
        next_page:,
        is_pinned:,
        pinned_items_remaining:,
        pagination_url: nil,
        this_user:
      )
        @pinnable_item = pinnable_item
        @is_first_item = is_first_item
        @has_more_items = has_more_items
        @next_page = next_page
        @is_pinned = is_pinned
        @pinned_items_remaining = pinned_items_remaining
        @pagination_url = pagination_url
        @this_user = this_user
      end

      private

      attr_reader :pinnable_item

      # Returns calculated attributes for the pinnable item <li> element
      def li_attributes
        class_names(
          "data-pinnable-type=repository",
          "data-pagination-src=#{data_pagination_src}"
        )
      end

      # Returns the value for data-pagination-src="" attribute
      def data_pagination_src
        if @is_first_item && @has_more_items
          @pagination_url
        else
          ""
        end
      end

      # Returns calculated attributes for the pinnable item <input> checkbox element
      def input_attributes
        class_names(
          "checked" => @is_pinned,
          "disabled" => @pinned_items_remaining < 1 && !@is_pinned,
          'data-targets="remote-pagination.focusMarkers"' => @is_first_item
        )
      end

      # Returns the octicon icon name depending on the pinnable item type and visibility
      def octicon_name
        if pinnable_item.public?
          "repo"
        elsif pinnable_item.internal?
          "organization"
        else
          "lock"
        end
      end

      # Returns a readable label for the associated octicon
      def octicon_label
        if pinnable_item.public?
          "public repo"
        elsif pinnable_item.internal?
          "internal repo"
        else
          "private repo"
        end
      end
    end
  end
end
