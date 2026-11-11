# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    module SelectMenu
      # An optional footer for the select menu.
      class MessageComponent < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>, including: `tag` (`Symbol`)
        # - HTML element type for the footer tag; defaults to `:footer`.
        def initialize(**system_arguments)
          @system_arguments = system_arguments
          @system_arguments[:tag] ||= :div
          @system_arguments[:classes] = class_names(
            "SelectMenu-message",
            system_arguments[:classes]
          )
        end

        def call
          render(Primer::BaseComponent.new(**@system_arguments)) { content }
        end
      end
    end
  end
end
