# typed: true
# frozen_string_literal: true

class UpdateIssueCommentOrchestration < IssueCommentOrchestration
  # updates need to be enqueued so disable validation.
  def validate_no_duplicates; end

  def only_save_on_orchestration_end? = true

  job_start

  step :touch_issue do
    T.bind(self, UpdateIssueCommentOrchestration)
    return unless issue = self.issue
    return if issue_comment.nil? || skip_touch_issue?

    issue.touch
  end

  sig { returns(T::Boolean) }
  def skip_touch_issue?
    !!data[:skip_touch_issue]
  end
end
