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

  def initialize(pull_request, user, merge_method, skip_checks: false)
    @pull_request = pull_request
    @user = user
    @merge_method = merge_method
    @evaluation_result = MergeConditions::EvaluationResult.new
    @skip_checks = skip_checks
  end

  def display_name
    raise NotImplemented
  end

  def description
    raise NotImplemented
  end

  def message
    raise NotImplemented
  end

  def async_condition
    raise NotImplemented
  end

  def async_evaluate
    async_condition.then { async_return_self }
  end

  def async_return_self
    Promise.new.fulfill(self)
  end

  sig { overridable.returns(T.any(PullRequests::PageData::MergeBox::MergeRequirementsPayload::GenericMergeConditionPayload, PullRequests::PageData::MergeBox::MergeRequirementsPayload::ConflictMergeConditionPayload, PullRequests::PageData::MergeBox::MergeRequirementsPayload::RepositoryRulesMergeConditionPayload, PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionWithSubConditionsPayload)) }
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
