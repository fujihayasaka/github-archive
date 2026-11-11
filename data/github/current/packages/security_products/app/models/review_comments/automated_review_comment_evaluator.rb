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

  sig { returns(T::Boolean) }
  def dismissable?
    false
  end

  sig { params(user: User).returns(T::Boolean) }
  def can_dismiss?(user:)
    false
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
  end

  sig { params(user: User).returns(T::Boolean) }
  def can_reopen?(user:)
    false
  end

  sig do
    params(
      comment: AutomatedReviewComment,
      user: User,
    ).void
  end
  def reopen(comment:, user:)
  end

  sig do
    params(
      comment: AutomatedReviewComment,
      user: User,
      pull: PullRequest,
    ).void
  end
  def apply_suggestion(comment:, user:, pull:)
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
  end

  sig do
    params(
      comment: AutomatedReviewComment,
    ).returns(T::Boolean)
  end
  def show_feedback_buttons?(comment:)
    false
  end

  sig { returns(T::Array[{ label: String, value: String }]) }
  def feedback_options
    []
  end

  sig { returns(T::Array[{ label: String, value: String, description: String }]) }
  def dismissal_options
    []
  end
end
