# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RuleRollups
    class RuleRollupMetadata
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { params(rule_suite: RuleEngine::RuleSuite, rule_type: String).void }
      def initialize(rule_suite, rule_type)
        @rule_suite = rule_suite
        @rule_type = rule_type
      end

      RuleSpecificMetadata = T.type_alias do
        T.any(
          PullRequestRollupMetadata::Payload,
          RequiredStatusCheckRollupMetadata::Payload,
          RequiredDeploymentRollupMetadata::Payload
        )
      end

      sig { abstract.returns(RuleSpecificMetadata) }
      def payload; end

      sig { params(include_evaluate_mode: T::Boolean).returns(T::Enumerable[RuleEngine::RuleRun]) }
      def rule_runs(include_evaluate_mode: false)
        @rule_suite.rule_runs.select { |run| run.rule_type == @rule_type }.filter { |run| include_evaluate_mode || !run.evaluate_mode? }
      end
    end
  end
end
