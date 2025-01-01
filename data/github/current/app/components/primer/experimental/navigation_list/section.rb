# typed: true
# frozen_string_literal: true

require "securerandom"

module Primer
  module Experimental
    class NavigationList # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      class Section < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
        attr_reader :id

        # Section heading.
        #
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
        renders_one :heading, lambda { |**system_arguments|
          T.bind(self, Primer::Experimental::NavigationList::Section)
          Heading.new(**T.unsafe({ section_id: id, **system_arguments }))
        }

        # Nav items.
        #
        # @param item_id [String]
        # @param selected [Boolean]
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
        renders_many :items, lambda { |component_klass: Item, **system_arguments|
          T.bind(self, Primer::Experimental::NavigationList::Section)

          system_arguments[:classes] = class_names(
            @item_classes,
            system_arguments[:classes]
          )

          component_klass.new(selected_item_id: @selected_item_id, **system_arguments)
        }

        renders_one :show_more_item, lambda { |component_klass: Item, **system_arguments|
          T.bind(self, Primer::Experimental::NavigationList::Section)

          system_arguments[:classes] = class_names(
            @item_classes,
            system_arguments[:classes]
          )
          system_arguments[:id] = "ActionList--showMoreItem"
          system_arguments[:hidden] = true
          system_arguments[:href] = "#"
          system_arguments["data-target"] = "lazy-load-section.showMoreItem"
          system_arguments["data-action"] = "click:lazy-load-section#submit"
          system_arguments["data-current-page"] = "1"
          component_klass.new(**system_arguments)
        }

        # @param selected_item_id [Symbol] The id of the selected item. Should correspond to one of the item ids in the list.
        # @param item_classes [Array<String>] Additional classes to add to the list's items.
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
        def initialize(selected_item_id: nil, item_classes: "", **system_arguments)
          @id = "nav-list-section-#{system_arguments[:id] || SecureRandom.uuid}"

          @system_arguments = system_arguments
          @system_arguments[:classes] = class_names(
            "ActionList",
            "ActionList--subGroup",
            @system_arguments[:classes]
          )

          @selected_item_id = selected_item_id
          @item_classes = item_classes
        end

        def before_render
          if heading.present?
            @system_arguments[:aria][:label] = nil
            @system_arguments[:"aria-label"] = nil
            @system_arguments[:"aria-labelledby"] = id
          else
            aria_label = aria(:label, @system_arguments)
            raise ArgumentError, "an aria-label is required" if aria_label.nil?
          end

          if show_more_item.present?
            @lazy_load_section = true
            @system_arguments[:"data-target"] = "lazy-load-section.list"
          end
        end
      end
    end
  end
end
