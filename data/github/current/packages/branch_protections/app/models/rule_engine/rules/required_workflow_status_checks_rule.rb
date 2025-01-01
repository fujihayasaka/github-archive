# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RequiredWorkflowStatusChecksRule < RefUpdateRule
      def initialize
        super(
          rule_name: "required_workflow_status_checks",
          display_name: "Require a pull request and required workflow checks to pass before merging",
          description: "Require all commits be made to a non-target branch and submitted via a pull request and required workflow checks to pass before they can be merged.")
      end

      def can_bypass?(rule_config, actor, repository, rule_run = nil)
        false # Required workflow cannot be bypassed
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        [:deletion]
      end

      def parameter_schema
        schema = ParameterSchema::Object.root
        schema.add_field(ParameterSchema::Field.new(name: "required_workflow_id", display_name: "Required workflow",
          type: :integer, required: true, description: "The required workflow id."))
        schema
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        # deprecated
        throw :abort
      end
    end
  end
end
