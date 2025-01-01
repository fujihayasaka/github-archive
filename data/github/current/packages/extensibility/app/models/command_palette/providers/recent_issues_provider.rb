# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class RecentIssuesProvider < IssuesProvider
      def self.debounce
        0
      end

      def self.type
        "prefetched"
      end

      def search(_)
        recent_items.map do |recent_item|
          issue_result(recent_item) if within_scope?(recent_item)
        end.compact
      end

      def recent_items
        GitHub.dogstats.distribution_time("command_palette.recent_issues_provider.latency") do
          ::Issue::RecentInteractions.new(
            current_user,
            since: 2.weeks.ago,
            types: [:issue, :pull_request],
            organization_id: scope.owner&.id,
          ).fetch(limit: 100).map(&:interactable)
        end
      end

      def issue_result(pr_or_issue)
        case pr_or_issue
        when Issue       then super(pr_or_issue, priority: 3)
        when PullRequest then super(pr_or_issue.issue, priority: 3)
        else
          raise "expected Issue or PullRequest, got #{pr_or_issue}"
        end
      end

      def within_scope?(pr_or_issue)
        if scope.repository
          pr_or_issue.repository == scope.repository
        elsif scope.owner
          pr_or_issue.repository.owner == scope.owner
        elsif scope.object.is_a?(Issue) || scope.object.is_a?(PullRequest)
          pr_or_issue.repository == scope.object.repository
        else
          true
        end
      end
    end
  end
end
