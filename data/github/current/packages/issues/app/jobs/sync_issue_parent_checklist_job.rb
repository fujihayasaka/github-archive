# typed: true
# frozen_string_literal: true

# Given an issue that has been updated, update all parent
# issues that are tracking this issue.
class SyncIssueParentChecklistJob < ApplicationJob
  MUTEX_GROUP_NAME = "sync_issue_parent_checklist"

  queue_as :sync_issue_parent_checklist

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(issue)
    return if issue.nil?

    issue.tracked_in_issues.each do |parent_issue|
      # When resolving the checkbox state, this is done per completed issue.
      # If multiple issues complete at the same time, multiple jobs are enqueued,
      # and this opens up for race conditions in the parent issue.
      #
      # Avoid this by protecting the checkbox state resolution by a mutex keyed
      # by parent issue ID.
      mutex_lock(parent_issue.id) do
        Issue.throttle_writes_with_retry do
          issue.resolve_checkbox_state(parent_issue, issue)
        end
      end
    end
  end

  private def mutex_lock(parent_issue_id, &block)
    mutex = GitHub::Redis::MutexGroup.new(MUTEX_GROUP_NAME, "parent_issue_#{parent_issue_id}", timeout: 30, wait: 30, sleep: 0.2)
    mutex.lock(&block)
  end
end
