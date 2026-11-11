# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    class NavigationList # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      # Items are rendered as styled links. They can optionally include leading and/or trailing visuals,
      # such as icons, avatars, and counters. Items are selected based on their item_id, which is a
      # required parameter. Items can also contain lists of subitems, which are rendered hidden but can
      # be expanded on click.
      class Item < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
        # The leading visual rendered before the link.
        #
        # @param kwargs [Hash] The arguments accepted by <%= link_to_component(Primer::Beta::Avatar) %> or <%= link_to_component(Primer::Beta::Octicon) %>
        renders_one :leading_visual, types: {
          icon: Primer::Beta::Octicon,
          avatar: lambda { |**kwargs|
            Primer::Beta::Avatar.new(**{ **kwargs, size: 16 })
          },
          svg: lambda { |**system_arguments|
            Primer::BaseComponent.new(**T.unsafe({ tag: :svg, **system_arguments }))
          },
          content: lambda { |**system_arguments|
            Primer::BaseComponent.new(**T.unsafe({ tag: :span, **system_arguments }))
          },
        }

        # The trailing visual rendered after the link.
        #
        # @param kwargs [Hash] The arguments accepted by <%= link_to_component(Primer::Beta::Octicon) %>, <%= link_to_component(Primer::Beta::Label) %>, or <%= link_to_component(Primer::Beta::Counter) %>
        renders_one :trailing_visual, types: {
          icon: Primer::Beta::Octicon,
          label: Primer::Beta::Label,
          counter: Primer::Beta::Counter
        }

        # Sub-items are also links. They are indented slightly and rendered underneath the item.
        #
        # @param component_klass [Class] A custom component class to use instead of the default SubItem class.
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
        renders_many :subitems, lambda { |component_klass: SubItem, **system_arguments|
          component_klass.new(selected_item_id: @selected_item_id, **system_arguments)
        }

        # @param selected_by_ids [String, Array] The unique identifier or identifiers used to determine if the item is selected.
        # @param href [String] The URL to link to.
        # @param selected_item_id [String] The id of the currently selected item in the whole list. Can refer to an item or subitem.
        # @param content_classes [String] Additional classes to add to the item's content, either an <a> or <button> tag.
        # @param submenu_classes [String] Additional classes to add to each of the item's subitems, i.e. each <li> tag.
        # @param disabled [Boolean] Whether or not the item is disabled. Disabled items are rendered as <button> tags instead of links.
        # @param expanded [Boolean] Whether or not the list of subitems is expanded or collapsed.
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
        def initialize(selected_by_ids: [], href: nil, selected_item_id: nil, content_classes: "", submenu_classes: "", disabled: false, expanded: false, truncate_label: false, content_attributes: {}, **system_arguments)
          @selected_by_ids = Array(selected_by_ids)
          @selected_item_id = selected_item_id
          @expanded = expanded
          @href = href
          @truncate_label = truncate_label

          @system_arguments = system_arguments
          @system_arguments[:"data-item-id"] = @selected_by_ids.join(" ")
          @system_arguments[:classes] = class_names(
            "ActionList-item",
            @system_arguments[:classes]
          )

          is_button = !@href || disabled

          @content_arguments = {
            tag: is_button ? :button : :a,
            type: is_button ? :button : nil,
            href: !is_button ? @href : nil,
            disabled: disabled,
            classes: class_names(
              "ActionList-content",
              "ActionList-content--visual16",
              content_classes
            ),
            **content_attributes
          }

          @submenu_arguments = {
            classes: class_names(
              "ActionList",
              "ActionList--subGroup",
              submenu_classes
            )
          }
        end

        # Whether or not the item is selected. Call only after defining subitems.
        #
        # @return [Boolean]
        def selected?
          if @selected_by_ids.present?
            @selected_by_ids.include?(@selected_item_id) && subitems.empty?
          elsif @href
            helpers.current_page?(@href, check_parameters: true)
          else
            false
          end
        end

        # Whether or not the item is expanded. Call only after defining subitems.
        #
        # @return [Boolean]
        def expanded?
          @expanded || subitems.any? { |subitem| subitem.selected? }
        end

        def before_render
          if subitems.present? && trailing_visual.present?
            raise RuntimeError, "Cannot render a trailing visual for an item with subitems"
          end

          if subitems.present?
            @content_arguments[:tag] = :button
            @content_arguments[:"aria-expanded"] = expanded?.to_s
            # Apply click handler to .ActionList-content button element, enables toggle behavior
            @content_arguments[:"data-action"] = "click:experimental-action-list#handleItemWithSubItemClick"
            # Apply click handler to .ActionList-item li element, enables highlight behavior
            @system_arguments[:"data-action"] = "click:experimental-action-list#handleItemClick"
          end

          if @system_arguments[:id] == "ActionList--showMoreItem"
            raise ArgumentError, "src is required for show_more_item" if @system_arguments[:src].blank?
            raise ArgumentError, "pages is required for show_more_item" if @system_arguments[:pages].blank?
          end

          @system_arguments[:classes] = class_names(
            selected? ? "ActionList-item--navActive" : "",
            subitems.present? ? "ActionList-item--hasSubItem" : "",
            @system_arguments[:classes]
          )

          @content_arguments[:"aria-current"] = "page" if selected?
          @content_arguments[:classes] = class_names(
            subitems.any?(&:selected?) ? "ActionList-content--hasActiveSubItem" : "",
            @content_arguments[:classes]
          )
        end
      end
    end
  end
end
