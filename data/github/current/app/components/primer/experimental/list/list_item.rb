# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    module List
      # `List::ListItem` is used inside `UnorderedList` and `OrderedList` to render a list item element.
      class ListItem < Primer::Component # rubocop:disable ViewComponent/ComponentsHaveUnitTests, ViewComponent/EncouragePreviewsForPrimer
        status :experimental

        # @example Default
        #
        #   <%= render(Primer::Experimental::List::ListItem.new) do %>
        #     ListItem
        #   <% end %>
        #
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
        def initialize(**system_arguments)
          @system_arguments = deny_tag_argument(**system_arguments)
          @system_arguments[:tag] = :li
        end

        def call
          render(Primer::BaseComponent.new(**@system_arguments)) { content }
        end
      end
    end
  end
end
