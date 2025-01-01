# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class CommitSignatureRule < CommitRule
      sig { void }
      def initialize
        super(
          rule_name: "ruleset_required_signatures",
          display_name: "Require signed commits",
          description: "Commits pushed to matching refs must have verified signatures.")
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_metadata_types
        [:commit]
      end

      sig { override.params(context: RuleEvaluationContext, rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
      def skip_evaluation?(context, rule_config)
        # Does not support protected branch configurations
        rule_config.provider_name == "protected_branch"
      end

      sig do
        override.params(
          context: RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_configs: T::Array[RepositoryRuleConfiguration],
          candidates: T::Array[MetadataSources::Types::Candidate],
        ).returns(T::Hash[RepositoryRuleConfiguration, T::Array[EvaluationResult]])
      end
      def bulk_evaluate_candidates(context, ref_update, rule_configs, candidates)
        evaluation_results_by_rule_config = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[RepositoryRuleConfiguration, T::Array[EvaluationResult]])

        candidate_state_by_commit_oid = T.let(candidates.each_with_object({}) do |candidate, h|
          h[T.cast(candidate, MetadataSources::Types::CommitCandidate).oid] = {
            candidate: candidate,
            commit: nil,
          }
        end, T::Hash[String, { candidate: MetadataSources::Types::Candidate, commit: T.nilable(Commit) }])

        commit_oids_with_signatures = candidate_state_by_commit_oid.filter_map do |oid, state|
          next unless state[:candidate].gpg_signature

          oid
        end

        context.repository.commits.find(commit_oids_with_signatures).each do |commit|
          T.must(candidate_state_by_commit_oid[commit.oid])[:commit] = commit
        end

        commits_with_signatures = candidate_state_by_commit_oid.values.filter_map { |state| state[:commit] }
        Commit.prefill_verified_signature(commits_with_signatures, context.repository, save_to_db: false) if commits_with_signatures.any?

        candidates.each do |candidate|
          rule_configs.each do |rule_config|
            commit = T.must(candidate_state_by_commit_oid[T.must(T.cast(candidate, MetadataSources::Types::CommitCandidate).oid)])[:commit]

            success = commit.nil? ? false : commit.verified_signature?
            T.must(evaluation_results_by_rule_config[rule_config]).push(EvaluationResult.new(candidate: candidate, success: success))
          end
        end

        evaluation_results_by_rule_config
      end

      sig do
        override.params(
          context: RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_config: RepositoryRuleConfiguration,
          violations: T::Array[Violation],
        )
        .returns(RuleRun)
      end
      def generate_evaluation_result(context, ref_update, rule_config, violations)
        return RuleRun.success(rule_config: rule_config, ref_update: ref_update) if violations.empty?

        RuleRun.failure(
          rule_config: rule_config,
          ref_update: ref_update,
          message: "Commits must have verified signatures.",
          violations: violations.map do |violation|
            {
              candidate: T.must(T.cast(violation.candidate, MetadataSources::Types::CommitCandidate).oid)
            }
          end
        )
      end
    end
  end
end
