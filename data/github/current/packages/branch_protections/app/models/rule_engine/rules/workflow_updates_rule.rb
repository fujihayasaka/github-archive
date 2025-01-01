# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class WorkflowUpdatesRule < RefUpdateRule

      def initialize
        super(rule_name: "workflow_updates",
          display_name: "Restricts updates to workflow files",
          description: "Workflow files cannot be modified.")
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        [:deletion]
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        workflow_update_decision = RefUpdates::WorkflowUpdatesPolicy.new(context.actor, context.repository)
          .check_ref_update(ref_update.before_oid, ref_update.after_oid)

        rule_configs.map do |rule_config|
          if workflow_update_decision.allowed?
            RuleRun.success(rule_config:, ref_update:)
          else
            RuleRun.failure(rule_config:, ref_update:, message: workflow_update_decision.short_message)
          end
        end
      end
    end
  end
end
