# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    # `UnorderedList` is a list component with unordered (bulleted) items.
    class UnorderedList < Primer::Component
      status :experimental

      # Use items to add list items to the unordered list.
      #
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      renders_many :items, Primer::Experimental::List::ListItem

      # @example UnorderedList with list items
      #
      #   <%= render(Primer::Experimental::UnorderedList.new) do |component| %>
      #     <% component.with_item do %>
      #       List item 1
      #     <% end %>
      #     <% component.with_item do %>
      #       List item 2
      #     <% end %>
      #   <% end %>
      #
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      def initialize(**system_arguments)
        @system_arguments = deny_tag_argument(**system_arguments)
        @system_arguments[:tag] = :ul
        @system_arguments[:classes] = class_names(
          "UnorderedList",
          system_arguments[:classes]
        )
      end

      def render?
        items.any?
      end
    end
  end
end
