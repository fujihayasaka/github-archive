# typed: true
# frozen_string_literal: true

class SyncIssueCountsForMilestoneJob < ApplicationJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :sync_issue_counts_for_milestone

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(id:)
    milestone = Milestone.find_by(id: id)

    if milestone
      milestone.update!(
        open_issue_count: milestone.issues.open_issues.count,
        closed_issue_count: milestone.issues.closed_issues.count
      )
    end
  end
end
