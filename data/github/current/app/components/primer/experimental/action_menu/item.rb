# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    class ActionMenu
      # This component is part of <%= link_to_component(Primer::Experimental::ActionMenu) %> and should not be
      # used as a standalone component.
      #
      # One of the following is required to apply functionality to the menu item: <%= one_of(Primer::Experimental::ActionMenu::Item::ACTION_OPTIONS) %>
      class Item < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
        attr_reader :disabled
        alias disabled? disabled

        TAG_OPTIONS = [:a, :button, :"clipboard-copy", :span].freeze
        ACTION_OPTIONS = [:classes, :onclick, :href, :value].freeze

        # Leading visuals appear to the left of the item text.
        #
        # Use:
        #
        # - `leading_visual_icon` for a <%= link_to_component(Primer::Beta::Octicon) %>.
        #
        # @param system_arguments [Hash] Same arguments as <%= link_to_component(Primer::Beta::Octicon) %>.
        renders_one :leading_visual, types: {
          icon: lambda { |**system_arguments|
            Primer::Beta::Octicon.new(classes: "ActionList-item-visual ActionList-item-visual--leading", **system_arguments)
          }
        }

        # @example Default
        #  <%= render Primer::Experimental::ActionMenu::Item.new(classes: "do-something-js") do %>
        #   Quote
        #  <% end %>
        #
        # @example Link
        #  <%= render Primer::Experimental::ActionMenu::Item.new(tag: :a, href: "https://primer.style/") do %>
        #   primer.style
        #  <% end %>
        #
        # @example Button
        #  <%= render Primer::Experimental::ActionMenu::Item.new(tag: :button, type: "button", onclick: "() => {}") do %>
        #   This does something
        #  <% end %>
        #
        # @example Clipboard copy
        #  <%= render Primer::Experimental::ActionMenu::Item.new(tag: :"clipboard-copy", value: "Text to be copied") do %>
        #   Copy text
        #  <% end %>
        # @param tag [Symbol] Optional. The tag to use for the item. <%= one_of(Primer::Experimental::ActionMenu::Item::TAG_OPTIONS) %>
        # @param is_divider [Boolean] Whether to render a divider.
        # @param is_dangerous [Boolean] If item should be styled dangerously.
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
        def initialize(tag: :span, is_divider: false, is_dangerous: false, disabled: false, **system_arguments)
          @is_divider = is_divider
          @is_dangerous = is_dangerous
          @disabled = disabled
          @tag = fetch_or_fallback(TAG_OPTIONS, tag, :span)
          @system_arguments = system_arguments

          return if @is_divider

          # check if system_arguments contains an action
          unless @system_arguments.keys.any? { |key| ACTION_OPTIONS.include?(key) }
            raise ArgumentError, "One of the following are required to apply functionality: #{ACTION_OPTIONS}"
          end

          @list_arguments = list_arguments
          @system_arguments[:classes] = class_names(
            system_arguments[:classes],
            "ActionList-content"
          )

          @system_arguments[:tag] = @tag
          @system_arguments[:role] = "menuitem"
          @system_arguments[:tabindex] = -1
          if disabled?
            @system_arguments[:"aria-disabled"] = true
            @system_arguments[:disabled] = "" if tag == :button
          end
        end

        def list_arguments
          args = {}
          args[:role] = "none"
          args[:tag] = :li
          if disabled?
            args[:"aria-disabled"] = true
          end

          args[:classes] = if @is_dangerous
            "ActionList-item ActionList-item--danger"
          else
            "ActionList-item"
          end

          args
        end
      end
    end
  end
end
