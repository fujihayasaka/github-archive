# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class UnpinIssue < ApplicationCommand
      scope_type "Issue"
      display_as "Unpin Issue", icon: "pin"

      def enabled?
        issue = scoped_object
        repository = issue.repository

        repository.has_issues? &&
          !repository.locked_on_migration? &&
          !repository.archived? &&
          issue.pinned? &&
          issue.repository.can_pin_issues?(current_user)
      end

      def execute
        issue = scoped_object
        issue.unpin(actor: current_user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        display_flash(type: :success, message: "Unpinned Issue: #{issue.title}")
      end
    end
  end
end
