# typed: strict
# frozen_string_literal: true

require "oss_license_compliance"
require "timeout"

module RuleEngine
  module Rules
    class LicenseComplianceScanningRule < RefUpdateRule
      RULE_NAME = "license_compliance_scanning"

      sig { void }
      def initialize
        super(
          rule_name: RULE_NAME,
          display_name: "Require license compliance results before merging",
          description: "Enforce any added or changed dependencies to comply with the organization's license policy.",
          feature_flag: :dependency_graph_license_compliance_rule,
          beta: true
        )
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "10.0.0" # TODO: Have put far future version to stop being in GHES
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        [:deletion]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_source_types
        [:organization, :business]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:branch]
      end

      sig { override.params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        # To avoid blocking PRs unnecessarily, this rule is optimistic and reports the license
        # compliance check as successful if anything causes the check to not run or not complete.
        repository = context.repository
        GitHub.tracer.in_span("RuleEngine::Rules::LicenseComplianceScanningRule#evaluate", attributes: { "gh.repo.id" => repository.id }) do
          if ref_update.is_a?(Git::Branch::Update) && ref_update.pull_request.present?
            success = T.let(true, T::Boolean)
            failure_message = T.let("", String)
            begin
              success, failure_message = Timeout.timeout(1) do
                OSSLicenseCompliance::RepositoryLicenseCompliance.check_compliance(
                  repository: repository,
                  pull_request: ref_update.pull_request)
              end
            rescue Timeout::Error
              GitHub.logger.info(
                "Timeout occurred while checking license compliance",
                "code.namespace": "RuleEngine::Rules::LicenseComplianceScanningRule",
                "code.function": "evaluate",
                "gh.repo.id": repository.id,
                "gh.pull_request.sha": ref_update.pull_request.head_sha,
              )

              # If the check times out, return failure to reflect that we don't know the true result
              # This shouldn't happen, because the check method is expected to return very quickly.
              return rule_configs.map { |config| RuleRun.failure(rule_config: config, ref_update: ref_update, message: "License compliance check timed out") }
            end

            unless success
              # If the compliance check fails, return a failure rule run.
              return rule_configs.map { |config| RuleRun.failure(rule_config: config, ref_update: ref_update, message: failure_message) }
            end
          end
          return rule_configs.map { |config| RuleRun.success(rule_config: config, ref_update: ref_update) }
        end

        # If this is not a branch update with a pull request, we skip the check
        rule_configs.map { |config| RuleRun.success(rule_config: config, ref_update: ref_update) }
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        sig { returns(T::Boolean) }
        def license_compliance_enabled?
          configs_by_type(RULE_NAME).any?
        end
      end
    end
  end
end
