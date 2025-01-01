# typed: true
# frozen_string_literal: true
module Primer
  module Experimental
    module SelectMenu
      # An optional header for the select menu.
      class HeaderComponent < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
        DEFAULT_CLOSEABLE = false
        DEFAULT_TITLE_TAG = :h3

        # @param closeable [Boolean] Whether to include a close button in the header for closing the whole menu.
        # @param title_tag [Symbol] HTML element type for the `.SelectMenu-title` tag; defaults to `:h3`.
        # @param title_classes [String] CSS classes to apply to the title element within the header.
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>, including: `tag` (`Symbol`)
        # - HTML element type for the header tag; defaults to `:header`.
        def initialize(
          closeable: DEFAULT_CLOSEABLE,
          title_tag: DEFAULT_TITLE_TAG,
          title_classes: nil,
          select_menu_id:,
          **system_arguments
        )
          @closeable = fetch_or_fallback_boolean(closeable, DEFAULT_CLOSEABLE)
          @title_tag = title_tag
          @title_classes = title_classes
          @select_menu_id = select_menu_id
          @system_arguments = system_arguments
          @system_arguments[:tag] ||= :header
          @system_arguments[:classes] = class_names(
            "SelectMenu-header",
            system_arguments[:classes]
          )
        end

        def closeable?
          @closeable
        end

        def wrapper_component
          Primer::BaseComponent.new(**@system_arguments)
        end

        def title_component
          Primer::BaseComponent.new(
            tag: @title_tag || DEFAULT_TITLE_TAG,
            classes: class_names(
              "SelectMenu-title",
              @title_classes,
            )
          )
        end

        # Private: Only used if `closeable` is `true`.
        def close_button_component
          Primer::Beta::CloseButton.new(
            aria: { label: "Close menu" },
            data: { "toggle-for": @select_menu_id },
          )
        end
      end
    end
  end
end
