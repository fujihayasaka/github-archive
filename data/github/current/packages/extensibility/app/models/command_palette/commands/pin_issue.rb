# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class PinIssue < ApplicationCommand
      scope_type "Issue"
      display_as "Pin Issue", icon: "pin"

      def enabled?
        issue = scoped_object
        repository = issue.repository

        repository.has_issues? &&
          !repository.locked_on_migration? &&
          !repository.archived? &&
          !issue.pinned? &&
          issue.repository.can_pin_issues?(current_user) &&
          repository.pinned_issues.count < Repository::PinnedIssuesDependency::PINNED_ISSUES_LIMIT
      end

      def execute
        issue = scoped_object
        issue.pin(actor: current_user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        display_flash(type: :success, message: "Pinned Issue: #{issue.title}")
      end
    end
  end
end
