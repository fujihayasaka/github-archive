# typed: true
# frozen_string_literal: true

module PullRequests
  module Stacks
    # A branch update that reports its target to the rule engine as the base
    # branch of the stack instead of the base branch of the PR.
    #
    # This allows us to run the rules from the base branch on PRs that are
    # higher up the stack.
    class RefUpdate < Git::Branch::Update
      def initialize(stack_base_ref:, **kwargs)
        @stack_base_ref = stack_base_ref

        super(**T.unsafe(kwargs))
      end

      sig { override.returns(T::Hash[Targeting::Attribute, T.untyped]) }
      def targetable_attributes
        {
          Targeting::Attribute::RefName => @stack_base_ref,
        }
      end
    end
  end
end
