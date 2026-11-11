# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    module SelectMenu
      # An optional filter bar for the select menu, to allow limiting how much of its contents
      # is shown at a time.
      class FilterComponent < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
        DEFAULT_PLACEHOLDER = "Filter"

        renders_one :input, -> (
          placeholder: DEFAULT_PLACEHOLDER,
          aria_label: DEFAULT_PLACEHOLDER,
          classes: "form-control",
          **system_arguments
        ) do
          T.bind(self, Primer::Experimental::SelectMenu::FilterComponent)

          system_arguments[:tag] = :input
          system_arguments[:type] = :text
          system_arguments[:placeholder] = placeholder
          system_arguments["aria-label"] = aria_label
          system_arguments[:classes] = class_names(
            "SelectMenu-input",
            classes,
          )

          Primer::BaseComponent.new(**system_arguments)
        end

        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>, including: `tag` (`Symbol`)
        # - HTML element type for the filter tag; defaults to `:form`.
        def initialize(list_id:, **system_arguments)
          @system_arguments = system_arguments
          @system_arguments[:tag] = :"filter-input"
          @system_arguments[:"aria-owns"] = list_id
          @system_arguments[:classes] = class_names(
            "SelectMenu-filter",
            system_arguments[:classes],
          )
        end

        def wrapper_component
          Primer::BaseComponent.new(**@system_arguments)
        end

        def before_render
          with_input(
            placeholder: @system_arguments[:placeholder] || DEFAULT_PLACEHOLDER,
            aria_label: DEFAULT_PLACEHOLDER,
            classes: "form-control"
          ) unless input?
        end
      end
    end
  end
end
