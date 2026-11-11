# typed: strict
# frozen_string_literal: true

module BranchProtections
  module Migration
    module Rules
      class DeletionMigrator < BaseRuleMigrator
        sig { override.returns(Symbol) }
        def rule_type
          RuleEngine::Rules::DeletionRule.new.rule_name.to_sym
        end

        sig { override.returns(String) }
        def display_name
          RuleEngine::Rules::DeletionRule.new.display_name
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

        sig { params(protected_branch: ::ProtectedBranch).returns(T::Array[Structs::BypassActor]) }
        def extract_bypass_actors(protected_branch)
          []
        end

        sig { override.params(protected_branch: ::ProtectedBranch).returns(String) }
        def enforcement_level(protected_branch)
          protected_branch.block_deletions_enforcement_level
        end
      end
    end
  end
end
