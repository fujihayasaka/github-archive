# typed: true
# frozen_string_literal: true

module Profiles
  module ProfilePins
    class PinnableItemComponent < ApplicationComponent
      include UsersHelper

      def initialize(
        pinnable_item:,
        is_first_item:,
        has_more_items:,
        next_page:,
        is_pinned:,
        pinned_items_remaining:,
        pagination_url: nil,
        this_user:,
        view_as:,
        dialog_location: nil
      )
        @pinnable_item = pinnable_item
        @is_first_item = is_first_item
        @has_more_items = has_more_items
        @next_page = next_page
        @is_pinned = is_pinned
        @pinned_items_remaining = pinned_items_remaining
        @pagination_url = pagination_url
        @this_user = this_user
        @view_as = view_as
        @dialog_location = dialog_location
      end

      private

      attr_reader :pinnable_item, :dialog_location

      # Indicates whether the pinnable item is Gist or Repository
      def is_gist?
        pinnable_item.is_a?(Gist)
      end

      # Indicates whether the pinnable item is public
      def is_public?
        !is_gist? && pinnable_item.public?
      end

      def is_internal?
        !is_gist? && pinnable_item.internal?
      end

      # Returns the pinnable item type (Gist or Repository)
      def type
        is_gist? ? "Gist" : "Repository"
      end

      # Returns calculated title for the pinnable item depending on its type and owner
      def title
        if is_gist?
          pinnable_item.title
        elsif pinnable_item.owner.display_login == @this_user.display_login
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

      # Returns calculated attributes for the pinnable item <li> element
      def li_attributes
        class_names(
          "data-pinnable-type=#{data_pinnable_type}",
          "data-pagination-src=#{data_pagination_src}"
        )
      end

      # Returns the value for data-pinnable-type="" attribute
      def data_pinnable_type
        is_gist? ? "gist" : "repository"
      end

      # Returns the value for data-pagination-src="" attribute
      def data_pagination_src
        if @is_first_item && @has_more_items
          @pagination_url || user_pinnable_items_path(@this_user.display_login, page: @next_page, view_as: @view_as, dialog_location: dialog_location)
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
        if is_gist?
          "code-square"
        elsif is_public?
          "repo"
        elsif is_internal?
          "organization"
        else
          "lock"
        end
      end

      # Returns a readable label for the associated octicon
      def octicon_label
        if is_gist?
          "gist"
        elsif is_public?
          "public repo"
        elsif is_internal?
          "internal repo"
        else
          "private repo"
        end
      end
    end # PinnableItemComponent
  end # ProfilePins
end # Profiles
