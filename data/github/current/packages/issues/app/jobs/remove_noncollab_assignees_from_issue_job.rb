# typed: true
# frozen_string_literal: true

class RemoveNoncollabAssigneesFromIssueJob < ApplicationJob
  queue_as :remove_noncollab_assignees_from_issue

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(issue_id)
    if issue = Issue.find_by(id: issue_id)

      with_write do
        Issue.throttle_with_retry { issue.remove_noncollab_assignees }
      end
    end
  end
end
