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
        pull_request.async_merge_method_statuses(actor: viewer),
      ]).then do |(base_repository, merge_queue_enabled, base_branch_rule_evaluator, merge_method_statuses)|
        default_merge_method = base_branch_rule_evaluator&.default_merge_method_for(viewer) || base_repository.default_merge_method_for(viewer)

        if merge_queue_enabled && merge_action == :direct_merge
          merge_queue_on_and_bypassable = !base_branch_rule_evaluator&.merge_queue_enforced_for?(actor: viewer)

          # returns direct merge methods when merge queue is enabled
          # Returns the appropriate allowable_status after checking for ability and permission to bypass rules
          [
            new(name: MERGE, allowable_status: merge_method_statuses[:merge] != :blocked && merge_queue_on_and_bypassable ? :allowed_with_bypass : :blocked, is_default: default_merge_method == :merge),
            new(name: SQUASH, allowable_status: merge_method_statuses[:squash] != :blocked && merge_queue_on_and_bypassable ? :allowed_with_bypass : :blocked, is_default: default_merge_method == :squash),
            new(name: REBASE, allowable_status: merge_method_statuses[:rebase] != :blocked && merge_queue_on_and_bypassable ? :allowed_with_bypass : :blocked, is_default: default_merge_method == :rebase)
          ]
        elsif merge_queue_enabled || merge_action == :merge_queue
          # returns merge queue methods
          # It will always return :allowed or :blocked, currently no support to enqueue in bypass mode
          allowable_merge_methods_for_merge_queue(
            repo: base_repository,
            branch: pull_request.base_ref,
          )
        else
          [
            new(name: MERGE, allowable_status: merge_method_statuses[:merge], is_default: default_merge_method == :merge),
            new(name: SQUASH, allowable_status: merge_method_statuses[:squash], is_default: default_merge_method == :squash),
            new(name: REBASE, allowable_status: merge_method_statuses[:rebase], is_default: default_merge_method == :rebase)
          ]
        end
      end
    end

    sig { returns(Symbol) }
    attr_reader :allowable_status

    attr_reader :name, :is_default

    # @param name [Symbol] the name of the merge method. One of MERGE, SQUASH, or REBASE.
    # @param allowable_status [Symbol] whether the merge method is allowable based on repo settings and repo rules. One of: allowed, blocked, or allowed_with_bypass.
    # @param is_default [Boolean] whether the merge method is the default merge method for the given user, based on repo settings and the user's last used merge method .
    sig { params(name: Symbol, allowable_status: Symbol, is_default: T::Boolean).void }
    def initialize(name:, allowable_status:, is_default:)
      @name = name
      @allowable_status = allowable_status
      @is_default = is_default
    end

    class << self
      private

      def allowable_merge_methods_for_merge_queue(repo:, branch:)
        merge_queue = MergeQueue.for(repository: repo, branch: branch)

        if merge_queue.nil?
          return [
            new(name: MERGE, allowable_status: :blocked, is_default: true),
            new(name: SQUASH, allowable_status: :blocked, is_default: false),
            new(name: REBASE, allowable_status: :blocked, is_default: false)
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
          new(name: MERGE, allowable_status: is_merge_method ? :allowed : :blocked,  is_default: is_merge_method),
          new(name: SQUASH, allowable_status: is_squash_method ? :allowed : :blocked, is_default: is_squash_method),
          new(name: REBASE, allowable_status: is_rebase_method ? :allowed : :blocked, is_default: is_rebase_method)
        ]
      end
    end
  end
end
