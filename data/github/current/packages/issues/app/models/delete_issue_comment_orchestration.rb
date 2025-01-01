# typed: true
# frozen_string_literal: true

class DeleteIssueCommentOrchestration < IssueCommentOrchestration
  def only_save_on_orchestration_end? = true

  job_start

  step :touch_issue do
    T.bind(self, DeleteIssueCommentOrchestration)
    return unless issue = self.issue
    return if skip_touch_issue?

    issue.touch
  end

  sig { returns(T::Boolean) }
  def skip_touch_issue?
    !!data[:skip_touch_issue]
  end
end
