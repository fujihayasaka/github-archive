# typed: strict
# frozen_string_literal: true

class PullRequest
  module StackDependency
    extend T::Helpers

    class LockedStackEntryReason < T::Enum
      enums do
        Merged = new("MERGED")
        InMergeQueue = new("IN_MERGE_QUEUE")
        AutoMergeEnabled = new("AUTO_MERGE_ENABLED")
      end
    end

    requires_ancestor { PullRequest }

    sig { params(other: T.class_of(PullRequest)).void }
    def self.included(other)
      other.has_one :stack_entry, ->(pull) { T.unsafe(self).where(repository_id: pull.repository_id) },
        class_name: "PullRequests::StackEntry",
        inverse_of: :pull_request,
        dependent: :destroy

      other.has_one :stack,
        through: :stack_entry,
        class_name: "PullRequests::Stack",
        dependent: :destroy
    end

    # Can this PR be modified in a stack?
    # Returns `false` if it is actively being auto-merged, siting in the merge queue, or merged.
    sig { returns(T::Boolean) }
    def stack_changes_allowed?
      !merged? && !auto_merging? && !in_merge_queue?
    end

    # Is this PR actively being auto-merged?
    sig { returns(T::Boolean) }
    def auto_merging?
      auto_merge_request&.persisted? || false
    end

    # Can this PR be removed from its stack?
    sig { returns(T::Boolean) }
    def is_unstackable? = if FeatureFlag.vexi.enabled?(:pull_request_stacks_prevent_unstacking_locked_prs, repository, default: false)
                            !stack_operation_locked?
                          else
                            !in_merge_queue? && !auto_merging?
                          end

    # If present, indicates why stack operations cannot be performed on this PR.
    sig { returns(T.nilable(LockedStackEntryReason)) }
    def locked_stack_entry_reason
      return LockedStackEntryReason::Merged if merged?
      return LockedStackEntryReason::InMergeQueue if in_merge_queue?
      return LockedStackEntryReason::AutoMergeEnabled if auto_merging?

      nil
    end

    # Is the PR ineligible for any action, such as removing, rebasing, adding to the stack
    # checks if merged or in merge queue or auto merge enabled
    sig { returns(T::Boolean) }
    def stack_operation_locked? = !locked_stack_entry_reason.nil?

    # Can other PRs be stacked on top of this PR?
    sig { returns(T::Boolean) }
    def can_stack_on_top? = !cross_repo? && !closed? && (!stacked? || top_of_stack?)

    # Is this PR a member of a stack?
    sig { returns(T::Boolean) }
    def stacked? = stack_entry.present?

    # Is this PR a member of a stack, and on top of that stack?
    sig { returns(T::Boolean) }
    def top_of_stack? = stacked? && stack_position == stack_size

    # The position of the PR in the stack. One-based, where 1 is the bottom
    # of the stack. `nil` if the PR is not in a stack.
    sig { returns(T.nilable(Integer)) }
    def stack_position = stack_entry&.position

    # The size of the stack this PR is a member of. `nil` if the PR is not in
    # a stack.
    sig { returns(T.nilable(Integer)) }
    def stack_size = stack&.entry_count

    # The base ref of the stack this PR is a member of, i.e. the base ref of
    # the PR at the bottom of the stack. `nil` if the PR is not in a stack.
    sig { returns(T.nilable(String)) }
    def stack_base_ref = stack_entry&.stack&.base_ref

    # The base sha of the stack this PR is a member of, i.e. the base sha of
    # the PR at the bottom of the stack. `nil` if the PR is not in a stack.
    sig { returns(T.nilable(String)) }
    def stack_base_sha = stack_entry&.stack&.base_sha

    # Similar to `#base_ref_name`, but prefers the stack base when the PR
    # is part of a stack.
    sig { returns(String) }
    def stack_or_pull_base_ref_name
      stacks_enabled = PullRequests::Stacks.enabled?(base_repository)

      if stacks_enabled && stack = self.stack
        safe_ref_name(stack.base_ref)
      else
        base_ref_name
      end
    end

    # Similar to `#display_base_ref_name`, but prefers the stack base when the
    # PR is part of a stack. Applies UTF-8 sanitization for display contexts.
    sig { returns(String) }
    def display_stack_or_pull_base_ref_name
      PullRequest.display_ref_name(stack_or_pull_base_ref_name)
    end
  end
end
