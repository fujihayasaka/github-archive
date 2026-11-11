# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class CodeCoverageRule < RefUpdateRule
      GENERIC_FAILURE_MESSAGE = "Could not check code coverage status."

      sig { void }
      def initialize
        super(
          rule_name: "code_coverage",
          display_name: "Restrict code coverage",
          description: "Enforce minimum code coverage thresholds on pull requests. When configured, uploaded coverage data must meet the specified criteria before changes can be merged.",
          feature_flag: :code_coverage_rule,
          beta: true,
        )
      end

      sig { override.returns(T::Boolean) }
      def publish_api
        false
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        # Code Coverage is part of code quality, which will not be available on GHES anytime soon.
        # We therefore set the minimum version to 3.99, to effectively disable it on GHES, as recommended in the docs.
        "3.99"
      end

      sig { override.returns(ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root

        schema.add_field(ParameterSchema::Field.new(
          name: "minimum_coverage",
          display_name: "Minimum coverage percentage",
          type: :float,
          required: false,
          description: "The absolute minimum code coverage percentage required. Pull requests with coverage below this threshold will be blocked.",
          allowed_range: (0.0..100.0),
        ))

        schema.add_field(ParameterSchema::Field.new(
          name: "max_coverage_drop",
          display_name: "Maximum coverage drop",
          type: :float,
          required: false,
          description: "The maximum percentage points that coverage may drop relative to the default branch. Pull requests that reduce coverage by more than this amount will be blocked.",
          allowed_range: (0.0..100.0),
        ))

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
        # We ignore creation and deletion events for branches, since we only care about updates to existing branches.
        # We ignore refs in the merge_queue, since we check for code coverage when the PR is added to the merge queue.
        [:creation, :deletion, :ref_in_merge_queue]
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[IRuleConfig]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        # In theory, customers could merge PRs indirectly by pushing to the target branch, e.g. via the git CLI.
        # In this case, we'd need to derive possible commit_oids as well as all (=possibly multiple) PRs from the RefUpdate.
        # We have currently decided not to support this scenario, as
        # * looking up PRs would add ~20ms latency
        # * we'd need to send check multiple possible commit_oids, since there are different potential merge types
        # * it's an uncommon workflow that can be easily mitigated by merging via the UI or API
        return fail_all(rule_configs, ref_update, "Code coverage checks require merging via API or UI.") unless ref_update.is_a?(Git::Branch::Update)

        return fail_all(rule_configs, ref_update, "Code coverage checks require a pull request.") unless ref_update.pull_request.present?

        results = call_turboquality(ref_update.pull_request, context.repository, rule_configs)

        rule_configs.map.with_index do |rule_config, idx|
          passed, message = results.fetch(idx, [false, nil])

          next RuleRun.success(rule_config: rule_config, ref_update: ref_update) if passed

          RuleRun.failure(
            rule_config: rule_config,
            ref_update: ref_update,
            message: message.presence || "Code coverage checks failed.",
          )
        end
      end

      private

      # Calls the TurboQuality CoverageQualityGates service to evaluate coverage rules.
      # Returns an array of [passed, failure_message] tuples, one per rule_config.
      sig do
        params(pull_request: PullRequest, repository: Repository, rule_configs: T::Array[IRuleConfig])
        .returns(T::Array[[T::Boolean, String]])
      end
      def call_turboquality(pull_request, repository, rule_configs)
        rules = rule_configs.map do |rule_config|
          Turboquality::Proto::CoverageRuleConfig.new(
            minimum_coverage: (rule_config.parameters["minimum_coverage"]&.to_f || 0.0) / 100.0,
            max_coverage_drop: (rule_config.parameters["max_coverage_drop"]&.to_f || 0.0) / 100.0,
          )
        end

        request = Turboquality::Proto::EvaluateCoverageRulesRequest.new(
          repository_id: repository.id,
          pr_number: pull_request.number,
          commit_oid: pull_request.head_sha,
          rules: rules,
        )

        response = GitHub::Turboquality.coverage_quality_gates_client.evaluate_coverage_rules(request)

        if (error = response.error)
          GitHub.logger.error("Turboquality CoverageQualityGates error: #{error.msg}")
          return rule_configs.map { [false, GENERIC_FAILURE_MESSAGE] }
        end

        response.data.results.map do |result|
          [result.passed, result.failure_message]
        end
      rescue StandardError => e
        tags = {
          "gh.repo.id": repository.id,
          "gh.pull_request.number": pull_request.number,
        }
        Failbot.report(e, tags)
        GitHub.logger.error("Code coverage rule evaluation failed: #{e.message}", tags)
        rule_configs.map { [false, GENERIC_FAILURE_MESSAGE] }
      end

      sig { params(rule_configs: T::Array[IRuleConfig], ref_update: Git::Ref::Update, message: String).returns(T::Array[RuleRun]) }
      def fail_all(rule_configs, ref_update, message)
        rule_configs.map do |rule_config|
          RuleRun.failure(rule_config:, ref_update:, message:)
        end
      end
    end
  end
end
