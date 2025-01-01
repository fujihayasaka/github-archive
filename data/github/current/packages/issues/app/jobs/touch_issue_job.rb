# typed: strict
# frozen_string_literal: true

class TouchIssueJob < ApplicationJob
  queue_as :touch_issue

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(issue_id: Integer, updated_at: Time).void }
  def perform(issue_id, updated_at)
    issue = Issue.find_by(id: issue_id)
    return unless issue
    return if issue.updated_at > updated_at

    with_write do
      issue.touch(time: updated_at)
    end
  end
end
