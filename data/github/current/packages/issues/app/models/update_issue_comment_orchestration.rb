# typed: true
# frozen_string_literal: true

class UpdateIssueCommentOrchestration < IssueCommentOrchestration
  # updates need to be enqueued so disable validation.
  def validate_no_duplicates; end

  def only_save_on_orchestration_end? = true
  def touch_issue_interval = 1

  job_start

  step :touch_issue do
    T.bind(self, UpdateIssueCommentOrchestration)
    return unless issue = self.issue
    return unless issue_comment = self.issue_comment
    return if skip_touch_issue?

    TouchIssueJob.enqueue_once_per_interval(
      args: [issue.id, issue_comment.updated_at],
      interval: touch_issue_interval,
      unique_id: issue.id
    )
  end
end
