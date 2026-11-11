# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class CopilotCodeReviewAnalysisToolsRule < RefUpdateRule

      CODEQL_TOOL = T.let("CodeQL".freeze, String)
      ESLINT_TOOL = T.let("ESLint".freeze, String)
      PMD_TOOL = T.let("PMD".freeze, String)

      sig { void }
      def initialize
        super(rule_name: "copilot_code_review_analysis_tools",
              display_name: "Manage static analysis tools in Copilot code review",
              description: "Copilot code review will include findings from the selected static analysis tools in its review comments.",
              feature_flag: :copilot_code_review_analysis_tools,
              beta: true)
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })

        tool_field = ParameterSchema::Field.new(name: "name", display_name: "The name of the tools that provide code review results.",
          type: :string, required: true, description: "The name of a code review analysis tool", default_value: CODEQL_TOOL, allowed_options: [
            {
              value: CODEQL_TOOL, display_name: "CodeQL"
            },
            {
              value: ESLINT_TOOL, display_name: "ESLint",
            },
            {
              value: PMD_TOOL, display_name: "PMD",
            }
          ])

        tool_schema = ParameterSchema::Object.new(name: "copilot_code_review_analysis_tool", display_name: "Code review analysis tool", description: "A tool that must provide code review results for this rule to pass.",
          default_value: {
            tool_field.name => tool_field.default_value,
          })

        tool_schema.add_field(tool_field)

        schema.add_field(ParameterSchema::Array.new(name: "tools", display_name: "Code review analysis tools", required: true, content_type: :object,
          default_value: [tool_schema.default_value], content_object: tool_schema, description: "Tools that must provide code review results for this rule.",
          ui_control: "copilot_code_review_analysis_tools"))

        schema
      end

      sig { override.params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.16"
      end

      # This will be a UI only rule until GA
      sig { override.returns(T::Boolean) }
      def publish_api
        false
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:branch]
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        # don't actually block anything
        []
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        sig { returns(T::Boolean) }
        def copilot_code_review_analysis_tools_enabled?
          configs_by_type("copilot_code_review_analysis_tools").any?
        end

        sig { returns(T::Boolean) }
        def copilot_code_review_analysis_tools_codeql_enabled?
          return true if configs_by_type("copilot_code_review_analysis_tools").empty?
          configs_by_type("copilot_code_review_analysis_tools").any? { |config| config.parameters["tools"].any? { |tool| tool["name"] == CODEQL_TOOL } }
        end

        sig { returns(T::Boolean) }
        def copilot_code_review_analysis_tools_eslint_enabled?
          configs_by_type("copilot_code_review_analysis_tools").any? { |config| config.parameters["tools"].any? { |tool| tool["name"] == ESLINT_TOOL } }
        end

        sig { returns(T::Boolean) }
        def copilot_code_review_analysis_tools_pmd_enabled?
          configs_by_type("copilot_code_review_analysis_tools").any? { |config| config.parameters["tools"].any? { |tool| tool["name"] == PMD_TOOL } }
        end
      end
    end
  end
end
