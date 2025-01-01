# typed: true
# frozen_string_literal: true

class CreateIssueCommentOrchestration < IssueCommentOrchestration
  def only_save_on_orchestration_end? = true

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

    if actor&.feature_enabled?(:issue_comment_create_orchestration_touch_cleanup)
      return if issue_transfer? || skip_touch_issue?

      issue.touch
    else
      return if skip_update_issue_orchestration? || issue_transfer?

      issue.touch if issue_previous_changes_empty?
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

  sig { returns(T::Boolean) }
  def skip_update_issue_orchestration?
    data[:skip_update_issue_orchestration].blank? ? false : data[:skip_update_issue_orchestration]
  end

  sig { returns(T::Boolean) }
  def skip_touch_issue?
    data[:skip_touch_issue].blank? ? false : data[:skip_touch_issue]
  end
end
