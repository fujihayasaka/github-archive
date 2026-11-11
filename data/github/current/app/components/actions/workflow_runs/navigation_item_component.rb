# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    # The primer/view_components library used to support the `show_on_hover:` option for
    # NavList items, but it was determined to be an inaccessible pattern and was therefore
    # removed. This component restores `show_on_hover:`'s behavior so as not to introduce
    # a visual regression. It should be used for the actions workflow runs UI _only_.
    class NavigationItemComponent < Primer::Beta::NavList::Item
      def initialize(...)
        super

        @trailing_action_show_on_hover = false
      end

      def with_trailing_action(show_on_hover: false, **system_arguments, &block)
        overrides = {}

        if show_on_hover
          overrides[:scheme] = :invisible
          @trailing_action_show_on_hover = true
        end

        super(**system_arguments, **overrides, &block)
      end

      private

      def before_render
        super

        return unless @trailing_action_show_on_hover

        @system_arguments[:classes] = class_names(
          @system_arguments[:classes],
          "ActionListItem--trailingActionHover"
        )
      end
    end
  end
end
