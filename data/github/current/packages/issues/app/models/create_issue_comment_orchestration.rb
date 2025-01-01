# typed: true
# frozen_string_literal: true

class CreateIssueCommentOrchestration < IssueCommentOrchestration
  def only_save_on_orchestration_end? = true
  def touch_issue_interval = 1

  job_start

  step :instrument_create_issue_comment do
    T.bind(self, CreateIssueCommentOrchestration)
    return if issue.nil? || issue_comment.nil? || issue_transfer?

    T.must(issue_comment).instrument_creation
  end

  step :attach_matching_assets do
    T.bind(self, CreateIssueCommentOrchestration)
    return if issue.nil? || issue_comment.nil? || issue_transfer?

    T.must(issue_comment).attach_matching_assets
  end

  step :subscribe_and_notify do
    T.bind(self, CreateIssueCommentOrchestration)
    return unless issue = self.issue
    return unless issue_comment = self.issue_comment
    return if issue_transfer?

    issue.subscribe(actor, :comment)
    issue_comment.subscribe_and_notify unless importing?
  end

  step :touch_issue do
    T.bind(self, CreateIssueCommentOrchestration)
    return unless issue = self.issue
    return unless issue_comment = self.issue_comment
    return if issue_transfer? || skip_touch_issue?

    if debounce_touch_issue?
      TouchIssueJob.enqueue_once_per_interval(
        args: [issue.id, issue_comment.updated_at],
        interval: touch_issue_interval,
        unique_id: issue.id
      )
    else
      issue.touch
    end
  end

  sig { returns(T::Boolean) }
  def issue_transfer?
    data[:issue_transfer].blank? ? false : data[:issue_transfer]
  end

  sig { returns(T::Boolean) }
  def issue_previous_changes_empty?
    data[:issue_previous_changes_empty].blank? ? false : data[:issue_previous_changes_empty]
  end
end
