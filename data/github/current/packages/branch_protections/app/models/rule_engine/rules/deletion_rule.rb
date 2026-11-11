# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class DeletionRule < RefUpdateRule

      def initialize
        super(rule_name: "deletion",
              display_name: "Restrict deletions",
              description: "Only allow users with bypass permissions to delete matching refs.")
      end

      def is_user_configurable?(source = nil)
        true
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.11"
      end

      # The deletion policy has no configuration: return the same result for each configuration
      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        if ref_update.deletion? && !ref_update.try(:allow_deletion_policy_bypass?)
          rule_configs.map { |pc| RuleRun.failure(rule_config: pc, ref_update: ref_update, message: "Cannot delete this #{ref_update.ref_type != "unknown" ? ref_update.ref_type : 'ref'}") }
        else
          rule_configs.map { |pc| RuleRun.success(rule_config: pc, ref_update: ref_update) }
        end
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        def block_deletions_enabled?
          configs_by_type("deletion").any?
        end

        def block_deletions_enforced_for?(actor:)
          enforced_rules_by_type("deletion", actor).any?
        end
      end
    end
  end
end
