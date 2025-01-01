# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RuleRollups
    class RequiredDeploymentRollupMetadata < RuleRollupMetadata
      extend T::Sig

      class Payload < T::Struct
        const :missingEnvironments, T::Array[String]
        const :deployedEnvironments, T::Array[String]
      end

      sig { params(rule_suite: RuleEngine::RuleSuite).void }
      def initialize(rule_suite)
        super(rule_suite, "required_deployments")
      end

      sig { override.returns(Payload) }
      def payload
        Payload.new(
          missingEnvironments: missing_environments,
          deployedEnvironments: deployed_environments
        )
      end

      sig { returns(T::Array[String]) }
      def missing_environments
        rule_runs.filter_map do |rule_run|
          if rule_run.evaluation_metadata && (results = rule_run.evaluation_metadata["deployment_results"])
            results.filter_map { |result| result["required"] unless result["deployment"] }
          end
        end.flatten.uniq
      end

      sig { returns(T::Array[String]) }
      def deployed_environments
        rule_runs.filter_map do |rule_run|
          if rule_run.evaluation_metadata && (results = rule_run.evaluation_metadata["deployment_results"])
            results.filter_map { |result| result["required"] if result["deployment"] }
          end
        end.flatten.uniq
      end
    end
  end
end
