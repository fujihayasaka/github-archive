# typed: true
# frozen_string_literal: true

class MergeConditions::Evaluator
  # Register additional merge conditions here
  CONDITIONS = T.let([
    ::MergeConditions::PullRequestState,
    ::MergeConditions::PullRequestRepoState,
    ::MergeConditions::PullRequestUserState,
    ::MergeConditions::PullRequestRules,
    ::MergeConditions::PullRequestMergeConflictState,
    ::MergeConditions::PullRequestMergeMethod,
    ::MergeConditions::Stack,
  ], T::Array[T.class_of(MergeConditions::BaseMergeCondition)])

  sig do
    params(
      pull_request: PullRequest,
      viewer: User,
      merge_method: T.nilable(Symbol),
      skip_checks: T::Boolean,
      enable_stacks: T::Boolean,
    ).returns(Promise[T::Array[MergeConditions::BaseMergeCondition]])
  end
  def self.async_evaluate(pull_request, viewer, merge_method, skip_checks:, enable_stacks:)
    if enable_stacks
      relevant_conditions = CONDITIONS
    else
      relevant_conditions = CONDITIONS - [::MergeConditions::Stack]
    end

    promises = relevant_conditions.map do |condition_class|
      condition_class.async_evaluate(pull_request, viewer, merge_method, skip_checks:)
    end
    Promise.all(promises).then do |results|
      results
    end
  end
end
