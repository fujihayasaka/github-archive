# typed: strict
# frozen_string_literal: true

class ReviewComments::DelegatedDismissalRequest
  class RequestStatus < T::Enum
    enums do
      Approved = new
      Rejected = new
      Pending = new
      Cancelled = new
    end

    sig do
      params(
        evaluation_result: Exemptions::ExemptionEvaluator::EvaluationResult
      ).returns(RequestStatus)
    end
    def self.from_exemptions_evaluation_result(evaluation_result)
      case evaluation_result
      when Exemptions::ExemptionEvaluator::EvaluationResult::Approved
        Approved
      when Exemptions::ExemptionEvaluator::EvaluationResult::Rejected
        Rejected
      when Exemptions::ExemptionEvaluator::EvaluationResult::Pending
        Pending
      when Exemptions::ExemptionEvaluator::EvaluationResult::Cancelled
        Cancelled
      end
    end
  end

  sig { returns(User) }
  attr_reader :requester

  sig { returns(T.nilable(String)) }
  attr_reader :reason

  sig { returns(RequestStatus) }
  attr_reader :status

  sig { returns(T.nilable(User)) }
  attr_reader :reviewer

  sig do
    params(
      requester: User,
      reason: T.nilable(String),
      status: RequestStatus,
      reviewer: T.nilable(User)
    ).void
  end
  def initialize(requester:, reason:, status:, reviewer:)
    @requester = requester
    @reason = reason
    @status = status
    @reviewer = reviewer
  end
end
