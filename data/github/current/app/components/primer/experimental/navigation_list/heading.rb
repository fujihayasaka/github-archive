# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    class NavigationList # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      # Section heading rendered above the section contents.
      class Heading < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
        # @param section_id [String] The unique identifier of the section the heading belongs to.
        # @param filled [Boolean] Whether or not the section is filled, i.e. has a colored background.
        # @param tag [Symbol] The heading tag to use for the section headings. Defaults to `:h3`.
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
        def initialize(section_id:, filled: false, tag: :h3, **system_arguments)
          @system_arguments = system_arguments
          @system_arguments[:tag] = :li
          @section_id = section_id
          @tag = tag
          @system_arguments[:classes] = class_names(
            "ActionList-sectionDivider",
            filled ? "ActionList-sectionDivider--filled" : "",
            @system_arguments[:classes]
          )
        end
      end
    end
  end
end
