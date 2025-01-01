# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class IssueResult < Result
      def self.type
        Issue
      end

      def self.create(issue, priority, context, group = nil)
        args = {
          priority: priority,
          title: "#{issue.title} ##{issue.number}",
          typeahead: issue.title,
          icon: Icons::Octicon.for(issue),
          action: Actions::JumpToAction.new(path: path_for_issue(issue)),
          group: group || :references,
          object: issue,
        }

        if !context.scope.repository? || context.scope.repository.id != issue.repository_id
          args[:subtitle] = "in #{issue.repository.nwo}"
        end

        if context.subject == issue
          args[:scope] = ResultScope.new(issue)
        end

        new(**args)
      end

      def self.path_for_issue(issue)
        repository = issue.repository
        owner = repository.owner

        if issue.pull_request?
          show_pull_request_path(owner, repository, issue)
        else
          issue_path(owner, repository, issue)
        end
      end
    end
  end
end
