# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class ReadyForReview < ApplicationCommand
      scope_type "PullRequest"
      display_as "Ready for Review"

      def enabled?
        scoped_object.can_mark_ready_for_review?(current_user)
      end

      def execute
        scoped_object.ready_for_review!(user: current_user)

        display_flash(type: :success, message: "Marked pull request as ready for review")
      end
    end
  end
end
