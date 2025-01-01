# typed: strict
# frozen_string_literal: true

class ReviewComments::Evaluators::CodeScanning < ReviewComments::AutomatedReviewCommentEvaluator

  sig { params(user: User).returns(T::Boolean) }
  def can_dismiss?(user:)
    @repository.code_scanning_writable_by?(user)
  end

  sig do
    params(
      comment: AutomatedReviewComment,
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def dismiss(comment:, user:, reason:, resolution_note:)
    code_scanning_reason = GitHub::Turboscan.to_resolution(reason)
    raise AutomatedReviewComment::ArgumentError, "Invalid reason: #{reason}" if code_scanning_reason.nil?

    # TODO: check for delegated dismissal

    CodeScanning::AlertDismissalService::close_alerts(
      repository: @repository,
      alert_numbers: [comment.resource_id.to_i],
      resolution: code_scanning_reason,
      resolver: user,
      resolution_note: resolution_note,
    ).first
  end

  sig { params(user: User).returns(T::Boolean) }
  def can_reopen?(user:)
    @repository.code_scanning_writable_by?(user)
  end

  sig do
    params(
      comment: AutomatedReviewComment,
      user: User,
    ).void
  end
  def reopen(comment:, user:)
    CodeScanning::AlertDismissalService::open_alert(
      repository: @repository,
      alert_number: comment.resource_id.to_i,
      refresh_reason: :ui_alert_update,
      resolver: user,
    )
  end

  sig do
    params(
      comment: AutomatedReviewComment,
      user: User,
      pull: PullRequest,
    ).void
  end
  def apply_suggestion(comment:, user:, pull:)
    response = GitHub::Turboscan::SuggestedFixes.apply_suggested_fix(
      repository_id: @repository.id,
      alert_number: comment.resource_id.to_i,
      ref_names_bytes: pull.build_ref_names_bytes_for_code_scanning_suggested_fix,
      actor_id: user.id,
      pull_request_id: pull.id,
    )

    GlobalInstrumenter.instrument("code_scanning.autofix_event", {
      repository_id: @repository.id,
      alert_number: comment.resource_id.to_i,
      event_type: :AUTOFIX_EVENT_TYPE_COMMITTED,
      pull_request_id: pull.id,
      pull_request_number: pull.number,
    })
  end

  sig do
    params(
      comment: AutomatedReviewComment,
      user: User,
      feedback: Symbol,
      choices: T::Array[Symbol],
      text_response: T.nilable(String),
    ).void
  end
  def feedback(comment:, user:, feedback:, choices:, text_response:)
    payload = {
      repository_id: @repository.id,
      user_analytics_tracking_id: user.analytics_tracking_id,
      pull_request_id: comment.pull_request&.id,
      pull_request_number: comment.pull_request&.number,
      alert_number: comment.resource_id,
      type: feedback,
      choice: choices,
      text_response: text_response,
    }

    GlobalInstrumenter.instrument("code_scanning.autofix_feedback", payload)
  end
end
