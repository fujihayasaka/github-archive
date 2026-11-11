# typed: true
# frozen_string_literal: true

class DeleteIssueCommentOrchestration < IssueCommentOrchestration
  def only_save_on_orchestration_end? = true
  def touch_issue_interval = 1

  job_start

  step :destroy_notification_summary do
    T.bind(self, DeleteIssueCommentOrchestration)
    return unless FeatureFlag.vexi.enabled?(:issues_delete_comment_destroy_summary_in_orchestration, repository, default: false)
    return unless issue = self.issue

    list = Newsies::List.new("Repository", repository_id)

    item_key = "IssueComment#{NotificationSummary::ITEM_KEY_SEPARATOR}#{issue_comment_id}"
    with_write do
      summary = NotificationSummary.by_thread(list, issue)
      if summary
        summary.send(:delete_item_by_key, item_key)
        summary.save!
      end
    end
  end

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
