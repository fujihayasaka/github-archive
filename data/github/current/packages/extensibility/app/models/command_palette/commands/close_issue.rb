# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class CloseIssue < ApplicationCommand
      scope_type "Issue"
      display_as "Close Issue"

      def enabled?
        issue = scoped_object
        repository = issue.repository

        repository.has_issues? &&
          !issue.closed? &&
          authorize_content(:issue, :update, repo: repository)
      end

      def execute
        scoped_object.close(current_user) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)

        display_flash(type: :success, message: "Closed issue")
      end
    end
  end
end
