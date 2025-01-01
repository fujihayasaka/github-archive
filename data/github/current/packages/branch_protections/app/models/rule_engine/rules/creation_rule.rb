# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class CreationRule < RefUpdateRule

      def initialize
        super(rule_name: "creation",
              display_name: "Restrict creations",
              description: "Only allow users with bypass permission to create matching refs.")
      end

      def is_user_configurable?(source = nil)
        true
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.11"
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        if ref_update.creation?
          rule_configs.map { |pc| RuleRun.failure(rule_config: pc, ref_update: ref_update, message: "Cannot create ref due to create name restrictions.") }
        else
          rule_configs.map { |pc| RuleRun.success(rule_config: pc, ref_update: ref_update) }
        end
      end
    end
  end
end
