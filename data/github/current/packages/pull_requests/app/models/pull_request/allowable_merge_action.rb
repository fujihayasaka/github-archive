# typed: true
# frozen_string_literal: true

class PullRequest
  class AllowableMergeAction < T::Struct
    # Returns an array of MergeActions the viewer could take.
    sig { params(pull_request: PullRequest, viewer: User).returns(Promise[[T.attached_class, T.attached_class]]) }
    def self.for(pull_request:, viewer:)
      Promise.all([
        pull_request.async_base_repository,
        pull_request.async_base_user,
        pull_request.async_repository,
        pull_request.async_merge_queue_enabled?,
        pull_request.async_batch_base_branch_rule_evaluator,
        pull_request.async_head_user
      ]).then do |result|
        base_repository, base_repo_owner, repository, pr_merge_queue_enabled, base_branch_rule_evaluator = result

        merge_queue = T.must(Platform::Enums::PullRequestMergeAction.values["MERGE_QUEUE"]).value
        direct_merge = T.must(Platform::Enums::PullRequestMergeAction.values["DIRECT_MERGE"]).value

        allowable_merge_queue_methods = PullRequest::AllowableMergeMethod.for(pull_request: pull_request, viewer: viewer, merge_action: merge_queue)
        allowable_direct_merge_methods = PullRequest::AllowableMergeMethod.for(pull_request: pull_request, viewer: viewer, merge_action: direct_merge)

        empty_result = [
          new(name: merge_queue, allowable_status: :blocked, merge_methods: allowable_merge_queue_methods),
          new(name: direct_merge, allowable_status: :blocked, merge_methods: allowable_direct_merge_methods),
        ]
        next empty_result unless base_repo_owner
        next empty_result unless base_repository.pushable_by?(viewer, ref: pull_request.base_ref_name)

        direct_merge_status = if pr_merge_queue_enabled
          base_branch_rule_evaluator&.merge_queue_enforced_for?(actor: viewer) ? :blocked : :allowed_with_bypass
        else
          :allowed
        end
        [
          new(name: merge_queue, allowable_status: pr_merge_queue_enabled ? :allowed : :blocked, merge_methods: allowable_merge_queue_methods),
          new(name: direct_merge, allowable_status: direct_merge_status, merge_methods: allowable_direct_merge_methods),
        ]
      end
    end

    const :name, Symbol
    const :allowable_status, Symbol
    const :merge_methods, Promise[T::Array[PullRequest::AllowableMergeMethod]]
  end
end
