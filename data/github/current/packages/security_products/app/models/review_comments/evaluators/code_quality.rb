# typed: strict
# frozen_string_literal: true

class ReviewComments::Evaluators::CodeQuality < ReviewComments::AutomatedReviewCommentEvaluator

  # Note(@aliceclv): we currently use code_scanning namespace for code quality
  # We should consider moving to code_quality
  FEEDBACK_OPTIONS = T.let({
    CODE_SCANNING_AUTOFIX_FEEDBACK_ALERT_NOT_RELEVANT: "The finding is not relevant, and no fix is needed",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_HAS_ERRORS: "The fix is partially correct, but has errors",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_IS_UNHELPFUL: "The fix is not helpful at all",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_WONT_ADDRESS_PROBLEM: "Unsure if this fix will address the security vulnerability",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_WILL_BREAK_FUNCTIONALITY: "Unsure if this fix will break code functionality",
    CODE_SCANNING_AUTOFIX_FEEDBACK_OTHER: "Other reason"
  }, T::Hash[Symbol, String])

  DISMISSAL_OPTIONS = T.let([
    { value: "FALSE_POSITIVE", label: "False positive", description: "This code is not valid" },
    { value: "USED_IN_TESTS", label: "Used in tests", description: "This code is not used in production" },
    { value: "WONT_FIX", label: "Won't fix", description: "This code is not relevant" },
  ], T::Array[{ value: String, label: String, description: String }])

  sig { returns(T::Boolean) }
  def dismissable?
    true
  end

  sig { params(user: User).returns(T::Boolean) }
  def can_dismiss?(user:)
    CodeQualityRepositoryPermissions.new(@repository).code_quality_writable_by?(user)
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
    CodeQualityRepositoryPermissions.new(@repository).code_quality_writable_by?(user)
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

  sig do
    params(
      comment: AutomatedReviewComment,
    ).returns(T::Boolean)
  end
  def show_feedback_buttons?(comment:)
    comment.has_suggestion?
  end

  sig { returns(T::Array[{ value: String, label: String }]) }
  def feedback_options
    FEEDBACK_OPTIONS.map do |value, label|
      { value: value.to_s, label: label }
    end
  end

  sig { returns(T::Array[{ value: String, label: String, description: String }]) }
  def dismissal_options
    DISMISSAL_OPTIONS
  end
end
