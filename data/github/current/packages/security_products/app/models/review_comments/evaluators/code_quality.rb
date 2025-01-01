# typed: strict
# frozen_string_literal: true

class ReviewComments::Evaluators::CodeQuality < ReviewComments::AutomatedReviewCommentEvaluator

  sig { params(user: User).returns(T::Boolean) }
  def can_dismiss?(user:)
    # Code quality doesn't have its own permissions yet, so we use the code scanning permissions
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
    # Do nothing for now until we know if we need to persist some else besides the comments
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
    # Do nothing for now until we know if we need to persist some else besides the comments
  end

  sig do
    params(
      comment: AutomatedReviewComment,
      user: User,
      pull: PullRequest,
    ).void
  end
  def apply_suggestion(comment:, user:, pull:)
    # Do nothing for now until we know if we need to persist some else besides the comments

    GlobalInstrumenter.instrument("code_quality.pr_finding_autofix_event", {
      repository_id: @repository.id,
      pull_request_id: pull.id,
      pull_request_number: pull.number,
      review_comment_id: comment.pull_request_review_comment_id,
      finding_stable_id: String(comment.resource_id.split(":")[1]), #TODO: better way of getting the stable_id
      event_type: :AUTOFIX_EVENT_TYPE_COMMITTED,
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
      review_comment_id: comment.pull_request_review_comment_id,
      finding_stable_id: comment.resource_id,
      type: feedback,
      choice: choices,
      text_response: text_response,
    }

    GlobalInstrumenter.instrument("code_quality.autofix_feedback", payload)
  end
end
