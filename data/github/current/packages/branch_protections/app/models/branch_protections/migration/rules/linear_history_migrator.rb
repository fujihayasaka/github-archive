# typed: strict
# frozen_string_literal: true

module BranchProtections
  module Migration
    module Rules
      class LinearHistoryMigrator < BaseRuleMigrator
        sig { override.returns(Symbol) }
        def rule_type
          RuleEngine::Rules::LinearHistoryRule.new.rule_name.to_sym
        end

        sig { override.returns(String) }
        def display_name
          RuleEngine::Rules::LinearHistoryRule.new.display_name
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
          protected_branch.linear_history_requirement_enforcement_level
        end
      end
    end
  end
end
