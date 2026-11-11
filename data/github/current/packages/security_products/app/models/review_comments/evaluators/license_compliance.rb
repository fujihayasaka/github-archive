# typed: strict
# frozen_string_literal: true

class ReviewComments::Evaluators::LicenseCompliance < ReviewComments::AutomatedReviewCommentEvaluator
  sig { params(user: User).returns(T::Boolean) }
  def can_dismiss?(user:)
    # TODO: We will implement dismissal logic later
    # We will need to check permissions to see if the user can dismiss license alerts
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
    # TODO: We will implement dismissal logic later
    # This will probably call OLC to update the license alert
  end
end
