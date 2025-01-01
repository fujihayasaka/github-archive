# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class MergeQueueLockedRefRule < RefUpdateRule

      def initialize
        super(rule_name: "merge_queue_locked_ref",
              display_name: "Block pushes to refs in the merge queue")
      end

      def can_bypass?(rule_config, actor, repository, rule_run = nil)
        false # merge queue locked ref policy policies cannot be overridden
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        # Ignore branch creations. They have no open PRs, and there wouldn't be a merge queue for a non-existent branch.
        [:creation]
      end

      # The merge queue locked ref policy has no configuration: return the same result for each configuration
      sig { override.params(context: RuleEvaluationContext, policies_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
      def bulk_evaluate(context, policies_by_ref_update)
        repository = context.repository

        # If the Merge Queue is no longer enabled, or the Merge Queue system bot
        # is making changes, those are always allowed.
        if !context.repo_merge_queue_enabled? || context.actor == MergeQueues.system_actor
          return policies_by_ref_update.flat_map do |ref_update, configs|
            success(ref_update, configs)
          end
        end

        delete_branch_on_merge = repository.delete_branch_on_merge?

        policies_by_ref_update.flat_map do |ref_update, configs|
          branch_name = ref_update.branch_name

          # When a merge group is marked as merged we do extra clean up if the setting for delete_branch_on_merge? is set
          # for a repository. We skip this check because the branch that we will be cleaning up is the pull request that
          # was just merged, and this is a ref update to delete, which will run branch protections again. At this point,
          # the queue has not been cleaned up yet, so the rules will fail this update since it will see that the ref is
          # _still_ in the queue.
          if ref_update.deletion? && delete_branch_on_merge
            next success(ref_update, configs)
          else
            configs.map do |config|
              RuleRun.failure(rule_config: config, ref_update: ref_update,
                message: merge_queue_locked_ref_denial_message)
            end
          end
        end
      end

      private

      def success(ref_update, configs)
        configs.map { |config| RuleRun.success(rule_config: config, ref_update: ref_update) }
      end

      def merge_queue_locked_ref_denial_message
        <<~MESSAGE
          A pull request for this branch has been added to a merge queue. Branches that
          are queued for merging cannot be updated. To modify this branch, dequeue the
          associated pull request.
        MESSAGE
      end
    end
  end
end
