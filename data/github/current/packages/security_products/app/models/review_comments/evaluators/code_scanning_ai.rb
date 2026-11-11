# typed: strict
# frozen_string_literal: true

class ReviewComments::Evaluators::CodeScanningAi < ReviewComments::AutomatedReviewCommentEvaluator
  # Feedback options for AI-detected code scanning findings
  FEEDBACK_OPTIONS = T.let({
    CODE_SCANNING_AI_FEEDBACK_FINDING_NOT_RELEVANT: "The finding is not relevant, and no fix is needed",
    CODE_SCANNING_AI_FEEDBACK_FIX_HAS_ERRORS: "The fix is partially correct, but has errors",
    CODE_SCANNING_AI_FEEDBACK_FIX_IS_UNHELPFUL: "The fix is not helpful at all",
    CODE_SCANNING_AI_FEEDBACK_FIX_WONT_ADDRESS_PROBLEM: "Unsure if this fix will address the security vulnerability",
    CODE_SCANNING_AI_FEEDBACK_FIX_WILL_BREAK_FUNCTIONALITY: "Unsure if this fix will break code functionality",
    CODE_SCANNING_AI_FEEDBACK_OTHER: "Other reason"
  }, T::Hash[Symbol, String])

  DISMISSAL_OPTIONS = T.let([
    {
      value: "FIX_APPLIED",
      label: "Fix applied",
      description: "Fix is applied",
    },
    {
      value: "WONT_FIX",
      label: "Won't fix",
      description: "Detection is accurate but you choose not to address it for a specific reason",
    },
    {
      value: "INACCURATE",
      label: "Inaccurate",
      description: "Finding is a false positive or otherwise incorrect",
    }
  ], T::Array[{ value: String, label: String, description: String }])

  sig { override.returns(T::Boolean) }
  def dismissable?
    true
  end

  sig { override.params(user: User, comment: T.nilable(AutomatedReviewComment)).returns(T::Boolean) }
  def can_dismiss?(user:, comment: nil)
    @repository.code_scanning_writable_by?(user)
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def dismiss(comment:, user:, reason:, resolution_note:)
    # Do nothing, conversation is resolved in dismiss! method of AutomatedReviewComment
  end

  sig { override.params(user: User).returns(T::Boolean) }
  def can_reopen?(user:)
    @repository.code_scanning_writable_by?(user)
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
    ).void
  end
  def reopen(comment:, user:)
    # Do nothing, conversation unresolved in reopen! method of AutomatedReviewComment
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
      pull: PullRequest,
    ).void
  end
  def apply_suggestion(comment:, user:, pull:)
    # AI findings may have suggestions - delegate to the suggestion application service
    # TODO: check if we should a Hydro event, consider adding a generic one for ARC
  end

  sig do
    override.params(
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
      finding_id: comment.resource_id,
      type: feedback,
      choice: choices,
      text_response: text_response,
    }
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
    ).returns(T::Boolean)
  end
  def show_feedback_buttons?(comment:)
    true # we want to show feedback for AI finding even if it doesn't have a suggestion
  end

  sig { override.returns(T::Array[{ value: String, label: String }]) }
  def feedback_options
    FEEDBACK_OPTIONS.map do |value, label|
      { value: value.to_s, label: label }
    end
  end

  sig { override.returns(T::Array[{ value: String, label: String, description: String }]) }
  def dismissal_options
    DISMISSAL_OPTIONS
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
    ).returns(T::Boolean)
  end
  def show_ai_note?(comment:)
    true
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
    ).returns(T::Boolean)
  end
  def show_ai_label?(comment:)
    true
  end

  sig do
    override.params(
      ar_comment: AutomatedReviewComment,
      pull_request: T.untyped,
      pull_request_review_comment: T.untyped,
      user: T.nilable(User),
    ).returns(T::Boolean)
  end
  def show_apply_changes_button?(ar_comment:, pull_request:, pull_request_review_comment:, user:)
    return false unless user
    return false unless ar_comment.suggestion_state_no_suggestion?

    PullRequests::Copilot::ApplyChangesHelper.can_apply_changes?(
      comment: pull_request_review_comment,
      pull_request: pull_request,
      user: user,
    )
  end
end
