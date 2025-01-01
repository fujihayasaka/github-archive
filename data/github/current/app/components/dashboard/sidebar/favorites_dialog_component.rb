# typed: true
# frozen_string_literal: true

module Dashboard
  module Sidebar
    class FavoritesDialogComponent < ApplicationComponent
      # Renders a dialog component that lazy loads a list of favorited repositories.
      # @param **system_arguments _[Optional]_ - A Hash of [system arguments](https://primer.style/view-components/system-arguments) or Primer::Experimental::Dialog arguments to be placed the `<modal-dialog>` element.
      def initialize(**system_arguments)
        @summary_args = summary_args || {}
        @system_arguments = system_arguments

        @system_arguments[:classes] = class_names(
          system_arguments[:classes],
          "dashboard-sidebar-favorites-modal",
          "js-favorites-details-component"
        )
      end

      private

      attr_reader :summary_args, :system_arguments
    end
  end
end
