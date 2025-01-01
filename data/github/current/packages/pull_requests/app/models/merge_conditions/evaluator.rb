# typed: true
# frozen_string_literal: true

class MergeConditions::Evaluator
  extend T::Sig

  # Register additional merge conditions here
  CONDITIONS = T.let([
    ::MergeConditions::PullRequestState,
    ::MergeConditions::PullRequestRepoState,
    ::MergeConditions::PullRequestUserState,
    ::MergeConditions::PullRequestRules,
    ::MergeConditions::PullRequestMergeConflictState,
    ::MergeConditions::PullRequestMergeMethod,
  ], T::Array[T.class_of(MergeConditions::BaseMergeCondition)])

  sig { params(pull_request: PullRequest, viewer: User, merge_method: T.nilable(Symbol)).returns(Promise[T::Array[MergeConditions::BaseMergeCondition]]) }
  def self.async_evaluate(pull_request, viewer, merge_method)
    promises = CONDITIONS.map do |condition_class|
      condition_class.async_evaluate(pull_request, viewer, merge_method)
    end
    Promise.all(promises).then do |results|
      results
    end
  end
end
