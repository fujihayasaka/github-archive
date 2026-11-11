# typed: strict
# frozen_string_literal: true

class ReviewComments::Evaluators::Copilot < ReviewComments::AutomatedReviewCommentEvaluator
  FEEDBACK_OPTIONS = T.let({
    OFFENSIVE_OR_DISCRIMINATORY: "Comment is harmful or unsafe",
    POORLY_FORMATTED: "Comment is poorly formatted",
    INCORRECT: "Comment is not true",
    UNHELPFUL: "Comment is not helpful",
    INCORRECT_LINE: "Comment is attached to the wrong line(s)",
    DUPLICATE: "Comment is a duplicate of another comment",
    SUGGESTION_OFFENSIVE_OR_DISCRIMINATORY: "Code suggestion is harmful or unsafe",
    SUGGESTION_POORLY_FORMATTED: "Code suggestion is poorly formatted",
    SUGGESTION_UNHELPFUL: "Code suggestion does not solve the problem in the comment",
    SUGGESTION_INVALID: "Code suggestion is invalid",
  }, T::Hash[Symbol, String])

  DISMISSAL_OPTIONS = T.let([
    { value: "FIX_APPLIED", label: "Fix applied", description: "A fix has been applied but the finding must be manually dismissed" },
    { value: "WONT_FIX", label: "Won't fix", description: "The detection is accurate but won't be addressed" },
    { value: "INACCURATE", label: "Inaccurate", description: "The suggestion is a false positive or completely incorrect" },
  ], T::Array[{ value: String, label: String, description: String }])

  EMPTY_DISMISSAL_OPTIONS = T.let([], T::Array[{ value: String, label: String, description: String }])

  sig { override.returns(T::Boolean) }
  def dismissable?
    FeatureFlag.vexi.enabled?(:code_quality_evaluate_ccr_comments, @repository, default: false) &&
      CodeQuality.enabled?(@repository)
  end

  sig { override.returns(T::Array[{ value: String, label: String, description: String }]) }
  def dismissal_options
    dismissable? ? DISMISSAL_OPTIONS : EMPTY_DISMISSAL_OPTIONS
  end

  sig { override.params(user: User, comment: T.nilable(AutomatedReviewComment)).returns(T::Boolean) }
  def can_dismiss?(user:, comment: nil)
    dismissable? &&
      CodeQualityRepositoryPermissions.new(@repository).code_quality_writable_by?(user)
  end

  sig { override.params(user: User).returns(T::Boolean) }
  def can_reopen?(user:)
    dismissable? &&
      CodeQualityRepositoryPermissions.new(@repository).code_quality_writable_by?(user)
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
    comment_id = comment.pull_request_review_comment_id.to_s
    pull_request_id = comment.pull_request_id

    custom_instructions_included = PullRequests::Copilot::CodeReviewComment.where(
      subject_id: comment_id,
      subject_type: "PullRequestReviewComment"
    ).where.not(copilot_instruction_type: nil).exists?

    PullRequests::Copilot::instrument_code_review_feedback(
      request_id: GitHub.context[:request_id],
      organization_id: @repository.owner&.organization? ? @repository.owner_id : nil,
      repository_id: @repository.id,
      pull_request_id:,
      comment_id:,
      comment_identifier: comment.resource_id,
      analytics_tracking_id: user.analytics_tracking_id,
      feedback: feedback.to_s,
      feedback_choice: choices.map { |c| c.to_s },
      text_response:,
      custom_instructions_included:,
      copilot_access_type: Copilot::Public::User.for(user).access_type,
      feedback_target: "arc_comment",
    )
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
    ).returns(T::Boolean)
  end
  def show_feedback_buttons?(comment:)
    true
  end

  sig { override.returns(T::Array[{ value: String, label: String }]) }
  def feedback_options
    FEEDBACK_OPTIONS.map do |value, label|
      { value: value.to_s, label: label }
    end
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
  def fold_long_suggestion?(comment:)
    true
  end

  sig { override.returns(T::Boolean) }
  def ai_authored?
    true
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
      pull: PullRequest,
    ).void
  end
  def apply_suggestion(comment:, user:, pull:)
    pr_review_comment = comment.pull_request_review_comment
    return if pr_review_comment.nil?

    thread = pr_review_comment.pull_request_review_thread
    reason = FeatureFlag.vexi.enabled?(:thread_resolution_reason, default: false) && thread&.copilot_code_review_thread? ? PullRequestReviewThread::RESOLUTION_REASON_ADDRESSED : nil
    thread&.resolve(resolver: user, resolution_reason: reason) unless thread&.resolved?
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
    # When a suggestion diff already exists, the "Apply Suggestion" flow is used instead.
    return false unless ar_comment.suggestion_state_no_suggestion?

    PullRequests::Copilot::ApplyChangesHelper.can_apply_changes?(
      comment: pull_request_review_comment,
      pull_request: pull_request,
      user: user,
    )
  end
end
