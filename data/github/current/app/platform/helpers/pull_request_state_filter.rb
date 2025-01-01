# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module PullRequestStateFilter
      def self.filter(scope, states)
        # slow query performance patch see: https://github.com/github/github/pull/87940 and
        # https://github.com/github/github/issues/80649#issuecomment-362265661 for more
        join_performance_patch = "`issues`.`repository_id` = `pull_requests`.`repository_id`"

        # We sort states and later sort by Array equality instead of inclusion
        # of one or two states. The case statement could have been reordered to
        # do `states.include?("open") && states.include?("closed")` and work, but
        # this ultimately felt more opaque than just sorting the small Array and
        # checking for exact equality.
        case states.sort
        when %w[closed]
          scope.where(merged_at: nil).joins(:issue).where(issues: { state: "closed" }).where(join_performance_patch)
        when %w[closed merged]
          scope.joins(:issue).where("merged_at IS NOT NULL OR issues.state = ?", "closed").where(join_performance_patch)
        when %w[closed open]
          scope.where(merged_at: nil)
        when %w[merged]
          scope.where("merged_at IS NOT NULL")
        when %w[merged open]
          scope.joins(:issue).where("pull_requests.merged_at IS NOT NULL OR issues.state = ?", "open").where(join_performance_patch)
        when %w[open]
          scope.joins(:issue).where(issues: { state: "open" }).where(join_performance_patch)
        else
          scope
        end
      end
    end
  end
end
