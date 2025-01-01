# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RuleRollups
    class PullRequestRollupMetadata < RuleRollupMetadata
      extend T::Sig

      class Payload < T::Struct
        const :requiredReviewers, Integer
        const :requiresCodeowners, T::Boolean
        const :failureReasons, T::Array[String]
      end

      sig { params(rule_suite: RuleEngine::RuleSuite).void }
      def initialize(rule_suite)
        super(rule_suite, "pull_request")
      end

      sig { override.returns(Payload) }
      def payload
        Payload.new(
          requiredReviewers: required_reviewers,
          requiresCodeowners: requires_codeowners,
          failureReasons: failure_reasons
        )
      end

      sig { returns(Integer) }
      def required_reviewers
        rule_runs.map(&:rule_config).compact
          .map { |rule_config| rule_config.param("required_approving_review_count") }.compact
          .max || 0
      end

      sig { returns(T::Boolean) }
      def requires_codeowners
        rule_runs.map(&:rule_config).compact
          .map { |rule_config| rule_config.param("require_code_owner_review") }.compact
          .any?
      end

      sig { returns(T::Array[String]) }
      def failure_reasons
        rule_runs.flat_map do |rule_run|
          payload = rule_run.evaluation_metadata["instrumentation_payload"]
          next [] unless payload
          reasons = []
          reasons << "code_owner_review_required" if !!payload["code_owner_review_required"]
          reasons << "thread_resolution_required" if !!payload["thread_resolution_required"]
          reasons << "soc2_approval_process_required" if !!payload["soc2_approval_process_required"]
          reasons << "changes_requested" if !!payload["has_requested_changes"]
          reasons << "more_reviews_required" if !!payload["approving_reviews_required"]
          reasons
        end.uniq
      end
    end
  end
end
