# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RuleRollups
    class RequiredStatusCheckRollupMetadata < RuleRollupMetadata

      class Payload < T::Struct
        const :statusCheckResults, T::Array[StatusCheckResult::Payload]
      end

      sig { params(rule_suite: RuleEngine::RuleSuite).void }
      def initialize(rule_suite)
        super(rule_suite, "required_status_checks")
      end

      sig { override.returns(Payload) }
      def payload
        Payload.new(
          statusCheckResults: status_check_results.map(&:payload),
        )
      end

      sig { returns(T::Array[StatusCheckResult]) }
      def status_check_results
        rule_runs.filter_map do |rule_run|
          if rule_run.evaluation_metadata && (results = rule_run.evaluation_metadata["check_results"])
            results.map do |result|
              check = result["checks"].first { |c| c["state"] != "success" } || result["checks"].first
              check_state = check&.fetch("state", nil) || "expected"

              StatusCheckResult.new(
                T.must(@rule_suite.repository),
                result["required"],
                result["integration_id"],
                check_state)
            end
          end
        end.flatten.uniq { |result| result.payload.serialize }
      end
    end
  end
end
