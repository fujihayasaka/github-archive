# typed: strict
# frozen_string_literal: true

class PullRequest
  module StackDependency
    extend T::Helpers

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

    # Can this PR be removed from its stack?
    sig { returns(T::Boolean) }
    def is_unstackable? = !in_merge_queue? && !auto_merge_request&.persisted?

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
    def stack_base_ref = stack&.base_ref

    # Similar to `#base_ref_name`, but prefers the stack base when the PR
    # is part of a stack.
    sig { returns(String) }
    def stack_or_pull_base_ref_name
      stacks_enabled = FeatureFlag.vexi.enabled?(
        :pull_request_stacks,
        base_repository,
        default: false
      )

      if stacks_enabled && stack = self.stack
        safe_ref_name(stack.base_ref)
      else
        base_ref_name
      end
    end
  end
end
