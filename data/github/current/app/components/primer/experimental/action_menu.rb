# typed: strict
# frozen_string_literal: true

module Primer
  module Experimental
    # The ActionMenu should be used when a user can select a single option triggering an action from a list of items. Primer will automatically nest an `Item` within a presentational `<li>` tag.
    #
    # The only allowed elements for the `Item` components are: `:a`, `:button`, and `:clipboard-copy`. If one isn't selected, a fallback `:span` will be used. To add functionality, use a `.js` class to create the functionality, or an `onclick` handler.
    #
    # @accessibility
    #   The action for the menu item needs to be on the element with `role="menuitem"`. Semantics are removed for everything nested inside of it. When a menu item is selected, the menu will close immediately.
    #
    #   Additional information around the keyboard functionality and implementation can be found on the [WAI-ARIA Authoring Practices](https://www.w3.org/TR/wai-aria-practices-1.2/#menu).
    class ActionMenu < Primer::Component
      # Button to activate the menu. This may be a <%= link_to_component(Primer::ButtonComponent) %> or <%= link_to_component(Primer::IconButton) %>.
      #
      # @param icon [Symbol] Set this to an [Octicon name](https://primer.style/octicons/) when you want to render an `IconButton`. Otherwise, this renders as a <%= link_to_component(Primer::ButtonComponent) %>.
      renders_one :trigger, lambda { |icon: nil, **system_arguments|
        T.bind(self, Primer::Experimental::ActionMenu)
        if icon
          # We can't use safe typing here until IconButton is typed
          Primer::Beta::IconButton.new(**T.unsafe({ scheme: :invisible, role: "button", icon: icon, "aria-haspopup": true, "aria-expanded": false, "aria-controls": list_id, id: menu_id, **system_arguments })) # rubocop:disable Primer/DeprecatedComponents
        else
          Primer::Beta::Button.new(scheme: :default, role: "button", "aria-haspopup": true, "aria-controls": list_id, "aria-expanded": false, id: menu_id, **system_arguments)
        end
      }

      # <%= link_to_component(Primer::Experimental::ActionMenu::Item) %>
      renders_many :items, "Primer::Experimental::ActionMenu::Item"

      ANCHOR_ALIGN_DEFAULT = :start
      ANCHOR_ALIGN_OPTIONS = T.let([ANCHOR_ALIGN_DEFAULT, :center, :end].freeze, T::Array[Symbol])

      ANCHOR_SIDE_DEFAULT = :outside_bottom
      ANCHOR_SIDE_OPTIONS = T.let([:outside_top, ANCHOR_SIDE_DEFAULT, :outside_left, :outside_right].freeze, T::Array[Symbol])

      DEFAULT_PRELOAD = T.let(false, T::Boolean)

      # @example Default
      #  <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-0") do |c| %>
      #    <% c.with_trigger { "Menu" } %>
      #    <% c.with_item(tag: :a, href: "https://primer.style/design/") do %>
      #      Primer Design
      #    <% end %>
      #    <% c.with_item(tag: :button, type: "button", onclick: "() => {}") do %>
      #      Quote Reply
      #    <% end %>
      #    <% c.with_item(tag: :"clipboard-copy", value: "Text to copy") do %>
      #      Copy Text
      #    <% end %>
      #  <% end %>
      #
      # @example With caret
      #  <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-1") do |c| %>
      #    <% c.with_trigger(with_caret: true) { "Menu" } %>
      #    <% c.with_item(tag: :a, href: "https://primer.style/design/") do %>
      #      Primer Design
      #    <% end %>
      #    <% c.with_item(tag: :button, type: "button") do %>
      #      Quote Reply
      #    <% end %>
      #    <% c.with_item(tag: :"clipboard-copy", value: "Text to copy") do %>
      #      Copy Text
      #    <% end %>
      #  <% end %>
      #
      # @example With `IconButton` trigger
      #   @description
      #     Set `icon:` to the octicon you want to use. Always provide an accessible name for the menu by setting `aria-label`.
      #   @code
      #    <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-2") do |c| %>
      #      <% c.with_trigger(icon: :"kebab-horizontal", "aria-label": "Menu") %>
      #      <% c.with_item(tag: :a, href: "https://primer.style/design/") do %>
      #        Primer Design Link
      #      <% end %>
      #      <% c.with_item(tag: :button, type: "button") do %>
      #        Quote Reply
      #      <% end %>
      #      <% c.with_item(tag: :"clipboard-copy", value: "Text to copy") do %>
      #        Copy Text
      #      <% end %>
      #    <% end %>
      #
      # @example With divider
      #  <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-3") do |c| %>
      #    <% c.with_trigger(icon: :"kebab-horizontal", "aria-label": "Menu") %>
      #    <% c.with_item(tag: :a, href: "https://primer.style/design/") do %>
      #      Primer Design Link
      #    <% end %>
      #    <% c.with_item(tag: :button, type: "button") do %>
      #      Quote Reply
      #    <% end %>
      #    <% c.with_item(is_divider: true) %>
      #    <% c.with_item(tag: :"clipboard-copy", value: "Text to copy") do %>
      #      Copy Text
      #    <% end %>
      #  <% end %>
      #
      # @example With danger item
      #  <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-4") do |c| %>
      #    <% c.with_trigger(icon: :"kebab-horizontal", "aria-label": "Menu") %>
      #    <% c.with_item(tag: :a, href: "https://primer.style/design/") do %>
      #      Primer Design Link
      #    <% end %>
      #    <% c.with_item(tag: :button, type: "button") do %>
      #      Quote Reply
      #    <% end %>
      #    <% c.with_item(tag: :"clipboard-copy", value: "Text to copy") do %>
      #      Copy Text
      #    <% end %>
      #    <% c.with_item(tag: :button, type: "button", is_dangerous: true) do %>
      #      Delete
      #    <% end %>
      #  <% end %>
      #
      # @example With center align
      #   @description
      #     Align the menu to the center of the trigger button
      #   @code
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-5", anchor_align: :center, anchor_side: :outside_top) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside top" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-6", anchor_align: :center, anchor_side: :outside_left) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside left" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #     <%= render Primer::Alpha::Experimental.new(menu_id: "my-action-menu-7", anchor_align: :center, anchor_side: :outside_right) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside right" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-8", anchor_align: :center, anchor_side: :outside_bottom) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside bottom" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #
      # @example With start align
      #   @description
      #     Align the menu to the start of the trigger button
      #   @code
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-9", anchor_align: :start, anchor_side: :outside_top) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside top" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-10", anchor_align: :start, anchor_side: :outside_left) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside left" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-11", anchor_align: :start, anchor_side: :outside_right) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside right" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-12", anchor_align: :start, anchor_side: :outside_bottom) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside bottom" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #
      # @example With end align
      #   @description
      #     Align the menu to the end of the trigger button
      #   @code
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-13", anchor_align: :end, anchor_side: :outside_top) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside top" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-14", anchor_align: :end, anchor_side: :outside_left) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside left" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-15", anchor_align: :end, anchor_side: :outside_right) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside right" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #     <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-16", anchor_align: :end, anchor_side: :outside_bottom) do |c| %>
      #       <% c.with_trigger(with_caret: true) { "Outside bottom" } %>
      #       <% c.with_item do %>
      #         Item 1 that does something
      #       <% end %>
      #       <% c.with_item do %>
      #         Item 2 that does another thing
      #       <% end %>
      #     <% end %>
      #
      # @example With deferred menu content loaded with an `include-fragment`
      #  <%= render Primer::Experimental::ActionMenu.new(menu_id: "my-action-menu-3", src: "/") do |c| %>
      #    <% c.with_trigger(icon: :"kebab-horizontal", "aria-label": "Menu") %>
      #  <% end %>
      #
      # @param menu_id [String] Id of the menu.
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      # @param anchor_align [Symbol] <%= one_of(Primer::Alpha::ActionMenu::ANCHOR_ALIGN_OPTIONS) %>
      # @param anchor_side [Symbol] <%= one_of(Primer::Alpha::ActionMenu::ANCHOR_SIDE_OPTIONS) %>
      # @param src [String] Used with an `include-fragment` element to load menu content from the given source URL.
      # @param preload [Boolean] When true, and src is present, loads the `include-fragment` on trigger hover.
      sig do
        params(
          menu_id: String,
          anchor_align: Symbol,
          anchor_side: Symbol,
          src: T.nilable(String),
          preload: T.nilable(T::Boolean),
          system_arguments: Primer::SystemArgumentsValue
        )
        .void
      end
      def initialize(
        menu_id:,
        anchor_align: ANCHOR_ALIGN_DEFAULT,
        anchor_side: ANCHOR_SIDE_DEFAULT,
        src: nil,
        preload: DEFAULT_PRELOAD,
        **system_arguments
      )
        @menu_id = menu_id
        @src = src
        @preload = T.let(fetch_or_fallback_boolean(preload, DEFAULT_PRELOAD), T::Boolean)
        @system_arguments = T.let(deny_tag_argument(**system_arguments), T::Hash[Symbol, T.untyped])

        if @src.present? && @preload == true
          @system_arguments[:preload] = true
        end

        @system_arguments[:tag] = :"experimental-action-menu"
        @system_arguments[:"data-anchor-align"] = fetch_or_fallback(ANCHOR_ALIGN_OPTIONS, anchor_align, ANCHOR_ALIGN_DEFAULT).to_s
        @system_arguments[:"data-anchor-side"] = fetch_or_fallback(ANCHOR_SIDE_OPTIONS, anchor_side, ANCHOR_SIDE_DEFAULT).to_s.dasherize
      end

      private

      sig { void }
      def before_render
        if @src.present? && items.any?
          raise ArgumentError, "you cannot use `items` when `src` is specified"
        end
      end

      sig { returns(String) }
      def menu_id
        "#{@menu_id}-text"
      end

      sig { returns(String) }
      def list_id
        "#{@menu_id}-list"
      end

      sig { returns(T::Boolean) }
      def render?
        items.any? || @src.present?
      end
    end
  end
end
