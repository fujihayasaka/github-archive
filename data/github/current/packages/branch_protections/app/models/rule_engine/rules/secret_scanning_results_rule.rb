# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class SecretScanningResultsRule < RefUpdateRule
      RULE_NAME = "secret_scanning_results"

      SECRET_TYPE_ALL = "all"
      SECRET_TYPE_DEFAULT = "default"

      sig { void }
      def initialize
        super(
          rule_name: RULE_NAME,
          beta: true,
          feature_flag: :secret_scanning_results_rule,
          display_name: "Require secret scanning alerts are resolved",
          description: "Choose which secret scanning results should block pull request merges. When configured, secret scanning alerts created from the pull request must be resolved before the changes can be merged.",
        )
      end

      sig { override.returns(ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })

        secret_type = ParameterSchema::Field.new(
          name: "secret_type",
          display_name: "Secret type",
          type: :string,
          required: true,
          description: "Which secret types should block merges. Default includes secrets matching provider patterns, custom patterns, and non-AI generic patterns. All includes default secret types and AI-detected secrets.",
          default_value: SECRET_TYPE_DEFAULT,
          allowed_options: [
            { value: SECRET_TYPE_ALL, display_name: "All", description: nil },
            { value: SECRET_TYPE_DEFAULT, display_name: "Default", description: nil },
          ],
        )

        schema.add_field(secret_type)
        schema
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:branch]
      end

      sig { override.params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.params(rule_config: IRuleConfig).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        [:creation, :deletion]
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[IRuleConfig]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        # Evaluation will be implemented in a follow-up (issue #823).
        rule_configs.map { |rule_config| RuleRun.success(rule_config:, ref_update:) }
      end

      sig { override.params(rule_config: IRuleConfig).returns(T::Boolean) }
      def blocks_new_direct_commits?(rule_config)
        true
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        sig { returns(T::Boolean) }
        def secret_scanning_results_enabled?
          configs_by_type("secret_scanning_results").any?
        end
      end
    end
  end
end
