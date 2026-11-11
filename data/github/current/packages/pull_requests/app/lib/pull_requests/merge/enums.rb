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
          Stack = new(:stack)
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
          InvalidStackState = new(:invalid_stack_state)
          MergeStrategyNotAllowed = new(:merge_strategy_not_allowed)
          BlockedByWorkflowUpdates = new(:blocked_by_workflow_updates)
          InvalidMergeQueueConfig = new(:invalid_merge_queue_config)
          AutoMergeNotAllowed = new(:auto_merge_not_allowed)
          AutoMergeCanNotBeAllowed = new(:auto_merge_can_not_be_allowed)
          BranchRuleFailure = new(:branch_rule_failure)
          ActorNotAuthorized = new(:actor_not_authorized)
        end

        # Maps each validation reason to a high-level rejection category for telemetry.
        #   :race_condition    - State changed between caller's check and backend validation
        #   :misconfiguration  - Repo/branch not configured for auto-merge
        #   :authorization     - User lacks required permissions
        #   :invalid_state     - PR is in a state where auto-merge doesn't apply
        sig { returns(Symbol) }
        def rejection_category
          case self
          when AdvisoryWorkspace, AutoMergeNotAllowed, AutoMergeCanNotBeAllowed,
               InvalidMergeQueueConfig, BranchRuleFailure
            :misconfiguration
          when ActorNotAuthorized
            :authorization
          when InvalidPullRequestState, MergeConflict
            :race_condition
          when InvalidUserState, InvalidRepositoryState, InvalidStackState,
               MergeStrategyNotAllowed, BlockedByWorkflowUpdates
            :invalid_state
          else
            T.absurd(self)
          end
        end
      end

      class DisableReason < T::Enum
        enums do
          # Disable-specific reasons
          BaseChangedByNonWriter = new(:base_changed_by_non_writer)
          MergeQueue = new(:merge_queue)
          Closed = new(:closed)
          ConvertedToDraft = new(:converted_to_draft)
          ManuallyDisabled = new(:manually_disabled)
          ParentMismatch = new(:parent_mismatch)
          PushFromNonWriter = new(:push_from_non_writer)
          Rewrite = new(:rewrite)
          WorkflowPolicyUpdateError = new(:workflow_policy_update_error)

          # Merge failure reasons
          BaseMissing = new(:base_missing)
          Denied = new(:denied)
          Draft = new(:draft)
          HeadMismatch = new(:head_mismatch)
          InvalidEmail = new(:invalid_email)
          MergeCommitBlocked = new(:merge_commit_blocked)
          NotMergeable = new(:not_mergeable)
          ProtectedBranch = new(:protected_branch)
          Rebase = new(:rebase)
          RebaseMergeBlocked = new(:rebase_merge_blocked)
          SquashMergeBlocked = new(:squash_merge_blocked)
          RepositoryRuleViolation = new(:repository_rule_violation)
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
          when BaseMissing
            "Base branch no longer exists"
          when Denied
            "Merge could not be authorized"
          when Draft
            "Pull request is a draft"
          when HeadMismatch
            "Head branch was modified"
          when InvalidEmail
            "Invalid email address"
          when MergeCommitBlocked
            "Merge commits are not allowed on this repository"
          when NotMergeable
            "Pull Request is not mergeable"
          when ProtectedBranch
            "Base branch requires signed commits"
          when Rebase
            "Rebase failed"
          when RebaseMergeBlocked
            "Rebase merges are not allowed on this repository"
          when SquashMergeBlocked
            "Squash merges are not allowed on this repository"
          when RepositoryRuleViolation
            "Repository rule violations found"
          else T.absurd(self)
          end
        end

      end
    end
  end
end
