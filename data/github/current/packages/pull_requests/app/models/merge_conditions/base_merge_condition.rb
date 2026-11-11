# typed: true
# frozen_string_literal: true

class MergeConditions::BaseMergeCondition
  extend T::Helpers

  abstract!

  sig { returns(PullRequest) }
  attr_reader :pull_request

  attr_reader :user

  sig { returns(T.nilable(Symbol)) }
  attr_reader :merge_method

  sig { returns(MergeConditions::EvaluationResult) }
  attr_reader :evaluation_result

  sig { returns(T::Boolean) }
  def skip_checks? = @skip_checks

  sig { params(pull_request: PullRequest, user: User, merge_method: T.nilable(Symbol), skip_checks: T::Boolean).returns(Promise[MergeConditions::BaseMergeCondition]) }
  def self.async_evaluate(pull_request, user, merge_method, skip_checks: false)
    new(pull_request, user, merge_method, skip_checks:).async_evaluate
  end

  sig { params(pull_request: PullRequest, user: User, merge_method: T.nilable(Symbol), skip_checks: T::Boolean).void }
  def initialize(pull_request, user, merge_method, skip_checks: false)
    @pull_request = pull_request
    @user = user
    @merge_method = merge_method
    @evaluation_result = MergeConditions::EvaluationResult.new
    @skip_checks = skip_checks
  end

  sig { abstract.returns(String) }
  def display_name; end

  sig { abstract.returns(String) }
  def description; end

  sig { abstract.returns(T.nilable(String)) }
  def message; end

  sig { abstract.returns(Promise[T.untyped]) }
  def async_condition; end

  sig { returns(Promise[MergeConditions::BaseMergeCondition]) }
  def async_evaluate
    async_condition.then { self }
  end

  sig { overridable.returns(PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionPayload) }
  def condition_payload
    PullRequests::PageData::MergeBox::MergeRequirementsPayload::GenericMergeConditionPayload.new(
      type: merge_condition_type,
      displayName: display_name,
      description: description,
      message: message,
      result: PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionResult.deserialize(result.to_s.upcase),
    )
  end

  sig { returns(Symbol) }
  def result
    evaluation_result.result
  end

  sig { returns(T::Boolean) }
  def failed? = result == MergeConditions::EvaluationResult::FAILED

  sig { returns(PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionType) }
  def merge_condition_type
    begin
      PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionType.deserialize(self.class.name&.demodulize&.underscore&.upcase)
    rescue
      PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionType.deserialize("UNKNOWN")
    end
  end

  class NotImplemented < StandardError; end
end
