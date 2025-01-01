# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    module SelectMenu
      # List items within the select menu.
      class ItemComponent < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
        DEFAULT_SELECTED = false
        DEFAULT_ICON = true

        attr_reader :divider

        # @param selected [Boolean] Whether item is the currently active one.
        # @param icon [Boolean] Whether or not to include a check Octicon when this item is selected.
        # @param divider [Boolean, String, nil] Whether to show a divider after item.
        # Pass `true` to show a simple line divider, or pass a String to show a divider with a title.
        # @param selectable [Boolean] Whether item is selectable. If it is not then the item will not highlight or be clickable.
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>, including: `tag` (`Symbol`)
        # - HTML element type for the item tag; defaults to `:button`. `role` (`String`)
        # - HTML role attribute for the item tag; defaults to `"menuitem"`.
        def initialize(
          selected: DEFAULT_SELECTED,
          icon: DEFAULT_ICON,
          divider: nil,
          selectable: true,
          **system_arguments
        )
          @selected = fetch_or_fallback_boolean(selected, DEFAULT_SELECTED)
          @icon = fetch_or_fallback_boolean(icon, DEFAULT_ICON)
          @divider = divider
          @system_arguments = system_arguments
          @system_arguments[:tag] ||= selectable ? :button : :div
          @system_arguments[:role] ||= if @selected || @icon
            "menuitemcheckbox"
          else
            "menuitem"
          end
          class_names = selectable ? ["SelectMenu-item"] : ["SelectMenu-header"]
          @system_arguments[:classes] = class_names(
            class_names,
            system_arguments[:classes],
          )
          if selectable
            @system_arguments[:"aria-checked"] = @selected ? "true" : "false"
          end
        end

        def wrapper_component
          case @system_arguments[:tag]
          when :button
            Primer::Beta::BaseButton.new(**@system_arguments)
          when :a
            @system_arguments.delete(:tag)
            Primer::Beta::Link.new(**@system_arguments)
          else
            Primer::BaseComponent.new(**@system_arguments)
          end
        end

        # Private: Only used if `icon`=`true`.
        def icon_component
          return unless @icon

          Primer::Beta::Octicon.new(
            icon: "check",
            classes: "SelectMenu-icon SelectMenu-icon--check",
          )
        end

        # Private: Only used if `divider` is non-nil.
        def divider_component
          Primer::BaseComponent.new(
            tag: divider.is_a?(String) ? :div : :hr,
            classes: "SelectMenu-divider"
          )
        end
      end
    end
  end
end
