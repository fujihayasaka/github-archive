# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Enums
      class Strategy < T::Enum
        enums do
          Merge = new(:merge)
          Squash = new(:squash)
          Rebase = new(:rebase)
        end

        sig { returns(Symbol) }
        def to_merge_method
          case self
          when Squash
            :auto_squash_and_merge
          when Rebase
            :auto_rebase_and_merge
          else
            :auto_merge
          end
        end

        sig { params(value: Symbol, default: Strategy).returns(Strategy) }
        def self.deserialize_with_default(value, default:)
          case value
          when :merge then Merge
          when :squash then Squash
          when :rebase then Rebase
          else default
          end
        end
      end

      class Runtime < T::Enum
        enums do
          Creation = new(:creation)
          Evaluation = new(:evaluation)
        end

        sig { returns(T::Boolean) }
        def creation? = self == Creation

        sig { returns(T::Boolean) }
        def evaluation? = self == Evaluation
      end

      class Signal < T::Enum
        enums do
          Done = new(:done)
          Restart = new(:restart)
          Waiting = new(:waiting)
          Errored = new(:errored)
        end
      end

      class Mode < T::Enum
        enums do
          Queue = new(:queue)
          Now = new(:now)
          WhenReady = new(:when_ready)
          Bypass = new(:bypass)
        end
      end

      class Mergeability < T::Enum
        enums do
          Unknown = new(:unknown)
          Clean = new(:clean)
          Dirty = new(:dirty)
          Blocked = new(:blocked)
          Behind = new(:behind)
          Unstable = new(:unstable)
          HasHooks = new(:has_hooks)
        end
      end

      class Validations < T::Enum
        enums do
          AdvisoryWorkspace = new(:advisory_workspace)
          MergeConflict = new(:merge_conflict)
          InvalidUserState = new(:invalid_user_state)
          InvalidPullRequestState = new(:invalid_pull_request_state)
          InvalidRepositoryState = new(:invalid_repository_state)
          MergeStrategyNotAllowed = new(:merge_strategy_not_allowed)
          BlockedByWorkflowUpdates = new(:blocked_by_workflow_updates)
          InvalidMergeQueueConfig = new(:invalid_merge_queue_config)
          AutoMergeNotAllowed = new(:auto_merge_not_allowed)
          AutoMergeCanNotBeAllowed = new(:auto_merge_can_not_be_allowed)
          BranchRuleFailure = new(:branch_rule_failure)
        end
      end

      class DisableReason < T::Enum
        enums do
          BaseChangedByNonWriter = new(:base_changed_by_non_writer)
          MergeQueue = new(:merge_queue)
          Closed = new(:closed)
          ConvertedToDraft = new(:converted_to_draft)
          ManuallyDisabled = new(:manually_disabled)
          ParentMismatch = new(:parent_mismatch)
          PushFromNonWriter = new(:push_from_non_writer)
          Rewrite = new(:rewrite)
          WorkflowPolicyUpdateError = new(:workflow_policy_update_error)
        end

        sig { returns(String) }
        def readable_message
          case self
          when BaseChangedByNonWriter
            "Base branch was changed by a user without write access"
          when MergeQueue
            "Merge queue setting changed"
          when Closed
            "Pull request was closed"
          when ConvertedToDraft
            "Pull request was converted to draft"
          when ManuallyDisabled
            "Manually disabled by user"
          when ParentMismatch
            "Base branch was modified"
          when PushFromNonWriter
            "Head branch was pushed to by a user without write access"
          when Rewrite
            "Could not re-write the merge commit for some reason"
          when WorkflowPolicyUpdateError
            "Tried to create or update workflow without `workflows` permission"
          end
        end

      end
    end
  end
end
