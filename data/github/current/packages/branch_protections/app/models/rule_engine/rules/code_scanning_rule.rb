# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class CodeScanningRule < RefUpdateRule
      include StatusHelper
      include Repositories::Domain::Provider

      SEVERITY_NONE = "none"
      SEVERITY_ERRORS = "errors"
      SEVERITY_ERRORS_AND_WARNINGS = "errors_and_warnings"
      SEVERITY_ALL = "all"

      SEVERITIES = T.let(Turboscan::Proto::EvalRefUpdateRulesRequest::SeverityChoice.descriptor.to_a.map { |name, value| [CodeScanningRule.const_get(name), value] }.to_h, T::Hash[String, Integer])

      SECURITY_SEVERITY_NONE = "none"
      SECURITY_SEVERITY_CRITICAL = "critical"
      SECURITY_SEVERITY_HIGH_OR_HIGHER = "high_or_higher"
      SECURITY_SEVERITY_MEDIUM_OR_HIGHER = "medium_or_higher"
      SECURITY_SEVERITY_ALL = "all"

      SECURITY_SEVERITIES = T.let(Turboscan::Proto::EvalRefUpdateRulesRequest::SecuritySeverityChoice.descriptor.to_a.map { |name, value| [CodeScanningRule.const_get(name), value] }.to_h, T::Hash[String, Integer])

      sig { void }
      def initialize
        super(
          rule_name: "code_scanning",
          display_name: "Require code scanning results",
          description: "Choose which tools must provide code scanning results before the reference is updated. When configured, code scanning must be enabled and have results for both the commit and the reference being updated.",
        )
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.14"
      end

      sig { override.returns(ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })

        tool_field = ParameterSchema::Field.new(name: "tool", display_name: "The name of the tool that must provide code scanning results.",
          type: :string, required: true, description: "The name of a code scanning tool", default_value: "CodeQL")

        alerts_threshold_field = ParameterSchema::Field.new(name: "alerts_threshold", display_name: "Alerts threshold",
          type: :string, required: true, description: %(The severity level at which code scanning results that raise alerts block a reference update. For more information on alert severity levels, see "[About code scanning alerts](${externalDocsUrl}/code-security/code-scanning/managing-code-scanning-alerts/about-code-scanning-alerts#about-alert-severity-and-security-severity-levels)."), default_value: SEVERITY_ERRORS, allowed_options: [
            { value: SEVERITY_NONE, display_name: "None", description: nil },
            { value: SEVERITY_ERRORS, display_name: "Errors", description: nil },
            { value: SEVERITY_ERRORS_AND_WARNINGS, display_name: "Errors and Warnings", description: nil },
            { value: SEVERITY_ALL, display_name: "All", description: nil },
          ])

        security_alerts_threshold_field = ParameterSchema::Field.new(name: "security_alerts_threshold", display_name: "Security alerts threshold",
          type: :string, required: true, description: %(The severity level at which code scanning results that raise security alerts block a reference update. For more information on security severity levels, see "[About code scanning alerts](${externalDocsUrl}/code-security/code-scanning/managing-code-scanning-alerts/about-code-scanning-alerts#about-alert-severity-and-security-severity-levels)."), default_value: SECURITY_SEVERITY_HIGH_OR_HIGHER, allowed_options: [
            { value: SECURITY_SEVERITY_NONE, display_name: "None", description: nil },
            { value: SECURITY_SEVERITY_CRITICAL, display_name: "Critical", description: nil },
            { value: SECURITY_SEVERITY_HIGH_OR_HIGHER, display_name: "High or higher", description: nil },
            { value: SECURITY_SEVERITY_MEDIUM_OR_HIGHER, display_name: "Medium or higher", description: nil },
            { value: SECURITY_SEVERITY_ALL, display_name: "All", description: nil }
          ])

        tool_schema = ParameterSchema::Object.new(name: "code_scanning_tool", display_name: "Code scanning", description: "A tool that must provide code scanning results for this rule to pass.",
          default_value: {
            tool_field.name => tool_field.default_value,
            alerts_threshold_field.name => alerts_threshold_field.default_value,
            security_alerts_threshold_field.name => security_alerts_threshold_field.default_value,
          })

        tool_schema.add_field(tool_field)
        tool_schema.add_field(security_alerts_threshold_field)
        tool_schema.add_field(alerts_threshold_field)

        schema.add_field(ParameterSchema::Array.new(name: "code_scanning_tools", display_name: "Code scanning tools", required: true, content_type: :object,
          default_value: [tool_schema.default_value], content_object: tool_schema, description: "Tools that must provide code scanning results for this rule to pass.",
          ui_control: "code_scanning_tools", validator: method(:ensure_valid_tools)))

        schema
      end

      sig { params(context: T.untyped, tools: T.untyped, errors: T.untyped).void }
      def ensure_valid_tools(context, tools, errors)
        errors << {
          error_code: :missing,
          message: "Please select at least one code scanning tool"
        } if tools.empty?
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
        repository = context.repository

        opts = if ref_update.is_a?(Git::Branch::Update) && ref_update.pull_request.present?
          is_dependabot = ->(author) { author&.bot? && author&.is_dependabot? }

          merge_commit_oid = ref_update.pull_request.merge_commit_sha
          if repository.feature_enabled?(:code_scanning_ruleset_cscs_merge_commit) || repository.owner&.feature_enabled?(:code_scanning_ruleset_cscs_merge_commit)
            merge_commit_oid = CodeScanningCheckSuite.merge_commit_for(pull_request: ref_update.pull_request)
          end

          {
            merge_commit_oid: ,
            head_commit_oid: ref_update.pull_request.head_sha,
            base_ref_bytes: ref_update.refname.b,
            # check if dependabot opened the pull request and made the most recent push,
            # if not then we expect an analysis to be provided for the commit the ref will be updated to
            # use logical short-circuit to avoid loading expensive push lookups unless
            # everything else checks out first
            is_dependabot: GitHub.dependabot_enabled? &&
              is_dependabot[ref_update.pull_request.user] &&
              is_dependabot[
                repositories_domain.pushes.latest_by_after_and_ref(
                            repository_id: ref_update.pull_request.repository_id,
                            ref: "refs/heads/#{ref_update.pull_request.head_ref_name}",
                            after: ref_update.pull_request.head_sha,
                          )&.pusher
              ]
          }
        else
          # if this was the merge queue then we checked for code scanning results when the add to merge queue button was pressed
          # eventually we may want to kick off a new analysis for the aggregate merge queue state, especially if we add
          # a strict mode that blocks on _any_ alerts being merged into the target branch
          if context.merge_queue_for(ref_update).present?
            GitHub.logger.info(
              "Skipping code scanning evaluation for merge queue ref update",
              "code.namespace": "RuleEngine::Rules::CodeScanningRule",
              "code.function": "evaluate",
              "gh.repo.id": repository.id,
            )
            return rule_configs.map { |rule_config| next RuleRun.success(rule_config:, ref_update:) }
          end

          {
            head_commit_oid: ref_update.after_oid,
            base_ref_bytes: ref_update.refname.b,
          }
        end

        # we only care about new alerts that might block a ref update (not deletions)
        file_changes = ::CodeScanning::PullRequestAlertSummaryGenerator.changed_lines(ref_update.diff, include_deletions: false)

        # Get code scanning alerts from Turboscan
        response = GitHub::Turboscan.eval_ref_update_rules(
          repository_id: repository.id,
          rule_configs: rule_configs.map do |rule_config|
            {
              tool_configs: rule_config.parameters.fetch("code_scanning_tools", []).map do |tool_config|
                {
                  name: tool_config["tool"],
                  alerts_threshold: SEVERITIES[tool_config["alerts_threshold"]],
                  security_alerts_threshold: SECURITY_SEVERITIES[tool_config["security_alerts_threshold"]],
                }
              end
            }
          end,
          file_changes:,
          **opts
        )

        if response&.error.present?
          TwirpHelper.report_twirp_error(response&.error)
        end

        # if results run out before rule_configs do (e.g: because they are nil/empty), use a generic failure message instead
        rule_results = response&.data&.results.to_a.chain([
          Turboscan::Proto::EvalRefUpdateRulesResponse::EvalResult.new(passed: false, failure_message: "Could not check code scanning status.")
        ].cycle)

        rule_configs.zip(rule_results).map do |rule_config, rule_result|
          rule_result = T.must(rule_result)
          if rule_result.passed
            next RuleRun.success(rule_config:, ref_update:)
          else
            next RuleRun.failure(rule_config:, ref_update:, message: rule_result.failure_message)
          end
        end
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
      def blocks_new_direct_commits?(rule_config)
        true
      end

      module StatusMethods
        extend T::Sig
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        sig { returns(T::Boolean) }
        def code_scanning_enabled?
          configs_by_type("code_scanning").any?
        end

        sig { returns(T::Boolean) }
        def codeql_required?
          configs_by_type("code_scanning").any? do |config|
            config.parameters.fetch("code_scanning_tools", []).any? do |tool_config|
              tool_config["tool"].casecmp("codeql") == 0
            end
          end
        end
      end
    end
  end
end
