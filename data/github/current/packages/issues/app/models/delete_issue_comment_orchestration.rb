# typed: true
# frozen_string_literal: true

class DeleteIssueCommentOrchestration < IssueCommentOrchestration
  def only_save_on_orchestration_end? = true
  def touch_issue_interval = 1

  job_start

  step :touch_issue do
    T.bind(self, DeleteIssueCommentOrchestration)
    return unless issue = self.issue
    return if skip_touch_issue?

    TouchIssueJob.enqueue_once_per_interval(
      args: [issue.id, Time.now],
      interval: touch_issue_interval,
      unique_id: issue.id
    )
  end
end
