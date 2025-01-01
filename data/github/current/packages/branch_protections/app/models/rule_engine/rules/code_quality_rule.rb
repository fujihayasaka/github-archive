# typed: strict
# frozen_string_literal: true

require "hydro/schemas/turboquality/v0/pull_request_analysis_pb"

module RuleEngine
  module Rules
    class CodeQualityRule < RefUpdateRule

      RULE_SEVERITY_NONE = "none"
      RULE_SEVERITY_ERROR = "errors"
      RULE_SEVERITY_NOTE = "notes"
      RULE_SEVERITY_WARNING = "warnings"

      SEVERITIES = T.let(Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity.descriptor.to_a.filter_map { |name, value| [CodeQualityRule.const_get(name), value] if name != :RULE_SEVERITY_UNKNOWN }.to_h, T::Hash[String, Integer])

      sig { void }
      def initialize
        super(
          rule_name: "code_quality",
          beta: false,
          feature_flag: :code_quality,
          display_name: "Require code quality results",
          description: "Choose which severity levels of code quality results should block pull request merges. When configured, a code quality result must be present on the pull request before the changes can be merged.",
        )
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.18"
      end

      sig { override.returns(ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })

        review_severity = ParameterSchema::Field.new(name: "severity", display_name: "Severity",
          type: :string, required: true, description: "The lowest severity level at which code quality reviews need to be resolved before commits can be merged.", default_value: RULE_SEVERITY_ERROR, allowed_options: [
            { value: RULE_SEVERITY_NONE, display_name: "None", description: nil },
            { value: RULE_SEVERITY_NOTE, display_name: "Notes", description: nil },
            { value: RULE_SEVERITY_WARNING, display_name: "Warnings", description: nil },
            { value: RULE_SEVERITY_ERROR, display_name: "Errors", description: nil },
          ])

        schema.add_field(review_severity)
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

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        [:creation, :deletion]
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        all_succeeded = rule_configs.map { |rule_config| RuleRun.success(rule_config:, ref_update:) }

        # If the ref update is not a branch update, we don't need to check for a code quality review
        return all_succeeded unless ref_update.is_a?(Git::Branch::Update)

        # If the ref update isn't for a pull request, we don't need to check for a code quality review
        pull_request = ref_update.pull_request
        return all_succeeded unless pull_request.present?

        # Skip evaluation if the repository does not have code quality enabled
        repository = context.repository
        return all_succeeded unless CodeQuality.enabled?(repository)

        n_analysis_configurations_expected = CodeScanning::AutoCodeql.new(repository).configuration.languages.count
        n_analysis_configurations_received = CodeQualityPullRequestAnalyses.received_analysis_configurations(repository:, pull_request:, commit_oid: pull_request.head_sha).count

        return rule_configs.map do |rule_config|
          RuleRun.failure(rule_config:, ref_update:, message: "code quality results are pending.")
        end unless n_analysis_configurations_expected == n_analysis_configurations_received

        # Get all code quality findings for the pull request
        findings = CodeQualityPullRequestFinding.find_all(repository:, pull_request:)
          .reject(&:fixed?) # Ignore findings that are already fixed
          .reject(&:resolved?) # Ignore findings that are resolved

        # no unfixed findings -> success
        return all_succeeded if findings.empty?

        rule_configs.map do |rule_config|
          rule_config_severity = rule_config.parameters.fetch("severity", RULE_SEVERITY_NONE)
          max_permissable_severity = SEVERITIES[rule_config_severity]

          next RuleRun.failure(rule_config:, ref_update:, message: "Severity #{rule_config_severity} not known") if max_permissable_severity.nil?

          findings_block_merge = findings.any? do |finding|
            finding_severity_value = finding.severity_value
            # If we cannot determine the severity of the finding, assume it blocks the merge
            finding_severity_value == Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::RuleSeverity::RULE_SEVERITY_UNKNOWN ||
              finding_severity_value >= max_permissable_severity
          end

          if findings_block_merge
            message = if rule_config_severity == RULE_SEVERITY_NONE
              "Code quality findings were detected."
            else
              "Code quality findings with severity of #{rule_config_severity.singularize} or above were detected."
            end
            RuleRun.failure(rule_config:, ref_update:, message:)
          else
            RuleRun.success(rule_config:, ref_update:)
          end
        end
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
      def blocks_new_direct_commits?(rule_config)
        true
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        sig { returns(T::Boolean) }
        def code_quality_enabled?
          configs_by_type("code_quality").any?
        end
      end
    end
  end
end
