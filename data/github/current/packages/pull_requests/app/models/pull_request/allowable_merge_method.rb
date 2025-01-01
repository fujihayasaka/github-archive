# typed: true
# frozen_string_literal: true

class PullRequest
  class AllowableMergeMethod
    MERGE = T.must(Platform::Enums::PullRequestMergeMethod.values["MERGE"]).value
    SQUASH = T.must(Platform::Enums::PullRequestMergeMethod.values["SQUASH"]).value
    REBASE = T.must(Platform::Enums::PullRequestMergeMethod.values["REBASE"]).value

    sig { params(pull_request: PullRequest, viewer: User, merge_action: T.nilable(Symbol)).returns(Promise[T::Array[T.attached_class]]) }
    def self.for(pull_request:, viewer:, merge_action: nil)
      Promise.all([
        pull_request.async_base_repository,
        pull_request.async_merge_queue_enabled?,
        pull_request.async_batch_base_branch_rule_evaluator,
        pull_request.cached_merge_state(viewer: viewer),
        pull_request.async_repository,
      ]).then do |(base_repository, merge_queue_enabled, batch_base_branch_rule_evaluator, cached_merge_state, repository)|
        Promise.all([
          pull_request.async_merge_commit_allowed?,
          pull_request.async_squash_merge_allowed?,
          pull_request.async_rebase_merge_allowed?,
          base_repository.async_network,
          repository.async_network,
        ]).then do |(merge_commit_allowed, squash_merge_allowed, rebase_merge_allowed)|
          can_bypass_branch_protections = cached_merge_state&.admin_override_possible?

          requires_linear_history = batch_base_branch_rule_evaluator&.required_linear_history_enabled?

          if base_repository.feature_enabled_for_source?(:pull_request_rule_merge_types)
            default_merge_method = batch_base_branch_rule_evaluator&.default_merge_method_for(viewer) || base_repository.default_merge_method_for(viewer)
          else
            default_merge_method = base_repository.default_merge_method_for(viewer)

            if default_merge_method == :merge && requires_linear_history
              default_merge_method = if squash_merge_allowed
                :squash
              else
                :rebase
              end
            end
          end

          if merge_queue_enabled && merge_action == :direct_merge
            # returns direct merge methods when merge queue is enabled
            # It will always return false for allowable, but checks for admin bypass ability
            [
              new(name: MERGE, is_allowable: false, is_allowable_with_bypass: merge_commit_allowed && can_bypass_branch_protections, is_default: default_merge_method == :merge),
              new(name: SQUASH, is_allowable: false, is_allowable_with_bypass: squash_merge_allowed && can_bypass_branch_protections, is_default: default_merge_method == :squash),
              new(name: REBASE, is_allowable: false, is_allowable_with_bypass: rebase_merge_allowed && can_bypass_branch_protections, is_default: default_merge_method == :rebase)
            ]
          elsif merge_queue_enabled || merge_action == :merge_queue
            # returns merge queue methods
            # It will always return false for is_allowable_with_bypass, currently no support to enqueue in bypass mod
            allowable_merge_methods_for_merge_queue(
              repo: base_repository,
              branch: pull_request.base_ref,
            )
          else
            [
              new(name: MERGE, is_allowable: merge_commit_allowed && !requires_linear_history, is_allowable_with_bypass: merge_commit_allowed && can_bypass_branch_protections, is_default: default_merge_method == :merge),
              new(name: SQUASH, is_allowable: squash_merge_allowed, is_allowable_with_bypass: squash_merge_allowed && can_bypass_branch_protections, is_default: default_merge_method == :squash),
              new(name: REBASE, is_allowable: rebase_merge_allowed, is_allowable_with_bypass: rebase_merge_allowed && can_bypass_branch_protections, is_default: default_merge_method == :rebase)
            ]
          end
        end
      end
    end

    attr_reader :name, :is_allowable, :is_allowable_with_bypass, :is_default

    # @param name [Symbol] the name of the merge method. One of MERGE, SQUASH, or REBASE.
    # @param is_allowable [Boolean] whether the merge method is allowable based on repo settings and repo rules.
    # @param is_allowable_with_bypass [Boolean] whether the merge method is allowed if the user can and does bypass the repo rules
    # @param is_default [Boolean] whether the merge method is the default merge method for the given user, based on repo settings and the user's last used merge method .
    sig { params(name: Symbol, is_allowable: T::Boolean, is_allowable_with_bypass: T::Boolean, is_default: T::Boolean).void }
    def initialize(name:, is_allowable:, is_allowable_with_bypass:, is_default:)
      @name = name
      @is_allowable = is_allowable
      @is_allowable_with_bypass = is_allowable_with_bypass
      @is_default = is_default
    end

    class << self
      private

      def allowable_merge_methods_for_merge_queue(repo:, branch:)
        merge_queue = MergeQueue.for(repository: repo, branch: branch)

        if merge_queue.nil?
          return [
            new(name: MERGE, is_allowable: false, is_allowable_with_bypass: false, is_default: true),
            new(name: SQUASH, is_allowable: false, is_allowable_with_bypass: false, is_default: false),
            new(name: REBASE, is_allowable: false, is_allowable_with_bypass: false, is_default: false)
          ]
        end

        config = MergeQueues.configuration_for(merge_queue)

        is_merge_method = false
        is_rebase_method = false
        is_squash_method = false

        case method = config.merge_method
        when MergeQueues::IConfiguration::MergeMethod::Merge
          is_merge_method = true
        when MergeQueues::IConfiguration::MergeMethod::Rebase
          is_rebase_method = true
        when MergeQueues::IConfiguration::MergeMethod::Squash
          is_squash_method = true
        else
          T.absurd(method)
        end

        [
          new(name: MERGE, is_allowable: is_merge_method, is_allowable_with_bypass: false, is_default: is_merge_method),
          new(name: SQUASH, is_allowable: is_squash_method, is_allowable_with_bypass: false, is_default: is_squash_method),
          new(name: REBASE, is_allowable: is_rebase_method, is_allowable_with_bypass: false, is_default: is_rebase_method)
        ]
      end
    end
  end
end
