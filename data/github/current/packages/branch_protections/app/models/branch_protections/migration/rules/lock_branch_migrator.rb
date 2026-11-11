# typed: strict
# frozen_string_literal: true

module BranchProtections
  module Migration
    module Rules
      class LockBranchMigrator < BaseRuleMigrator
        sig { override.returns(Symbol) }
        def rule_type
          RuleEngine::Rules::UpdateRule.new.rule_name.to_sym
        end

        sig { override.returns(String) }
        def display_name
          RuleEngine::Rules::UpdateRule.new.display_name
        end

        sig { override.params(protected_branch: ::ProtectedBranch).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def parameters(protected_branch)
          {
            update_allows_fetch_and_merge: protected_branch.lock_allows_fetch_and_merge
          }
        end

        sig do
          override.params(
            protected_branch: ::ProtectedBranch,
            rulesets: T::Array[::RepositoryRuleset]
          ).returns(T::Boolean)
        end
        def verify(protected_branch, rulesets)
          raise NotImplementedError
        end

        private

        sig { override.params(protected_branch: ::ProtectedBranch).returns(String) }
        def enforcement_level(protected_branch)
          protected_branch.lock_branch_enforcement_level
        end
      end
    end
  end
end
