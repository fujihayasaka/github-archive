# typed: strict
# frozen_string_literal: true

class ReviewComments::AutomatedReviewCommentEvaluator
  extend T::Helpers

  abstract!

  sig { returns(Repository) }
  attr_reader :repository

  sig { params(repository: Repository).void }
  def initialize(repository)
    @repository = repository
  end

  sig { overridable.returns(T::Boolean) }
  def dismissable?
    false
  end

  sig { overridable.returns(T::Boolean) }
  def delegated_dismissal_enabled?
    false
  end

  sig { overridable.params(user: User, comment: T.nilable(AutomatedReviewComment)).returns(T::Boolean) }
  def can_dismiss?(user:, comment: nil)
    false
  end

  sig do
    overridable.params(
      comment: AutomatedReviewComment,
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def dismiss(comment:, user:, reason:, resolution_note:)
  end

  sig do
    overridable.params(
      comment: AutomatedReviewComment,
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def request_dismissal(comment:, user:, reason:, resolution_note:)
  end

  sig { overridable.params(user: User).returns(T::Boolean) }
  def can_reopen?(user:)
    false
  end

  sig do
    overridable.params(
      comment: AutomatedReviewComment,
      user: User,
    ).void
  end
  def reopen(comment:, user:)
  end

  sig do
    overridable.params(
      comment: AutomatedReviewComment,
      user: User,
      pull: PullRequest,
    ).void
  end
  def apply_suggestion(comment:, user:, pull:)
  end

  sig do
    overridable.params(
      comment: AutomatedReviewComment,
      user: User,
      feedback: Symbol,
      choices: T::Array[Symbol],
      text_response: T.nilable(String),
    ).void
  end
  def feedback(comment:, user:, feedback:, choices:, text_response:)
  end

  sig do
    overridable.params(
      comment: AutomatedReviewComment,
    ).returns(T::Boolean)
  end
  def show_feedback_buttons?(comment:)
    false
  end

  sig { overridable.returns(T::Array[{ label: String, value: String }]) }
  def feedback_options
    []
  end

  sig do
    overridable.params(
      comment: AutomatedReviewComment,
    ).returns(T::Boolean)
  end
  def show_ai_note?(comment:)
    false
  end

  sig { overridable.returns(T::Array[{ label: String, value: String, description: String }]) }
  def dismissal_options
    []
  end

  sig do
    overridable.params(
      ar_comment: AutomatedReviewComment,
      pull_request: T.untyped,
      pull_request_review_comment: T.untyped,
      user: T.nilable(User),
    ).returns(T::Boolean)
  end
  def show_apply_changes_button?(ar_comment:, pull_request:, pull_request_review_comment:, user:)
    false
  end

  sig do
    overridable.params(
      comment: AutomatedReviewComment
    ).returns(T.nilable(ReviewComments::DelegatedDismissalRequest))
  end
  def current_delegated_dismissal_request(comment:)
    nil
  end
end
