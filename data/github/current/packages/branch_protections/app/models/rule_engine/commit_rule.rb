# typed: strict
# frozen_string_literal: true

module RuleEngine
  # Abstract base class for controlled push based rules
  class CommitRule < BaseRule
    abstract!

    sig { params(rule_name: String, display_name: String, description: T.nilable(String), feature_flag: T.nilable(Symbol), beta: T::Boolean, beta_api: T::Boolean).void }
    def initialize(rule_name:, display_name:, description: nil, feature_flag: nil, beta: false, beta_api: false)
      super(rule_name:, display_name:, description:, feature_flag:, beta:, beta_api:)
    end

    sig { abstract.returns(T::Array[Symbol]) }
    def supported_metadata_types; end

    sig do
      overridable.params(
        context: RuleEvaluationContext,
        ref_update: Git::Ref::Update,
        rule_configs: T::Array[RepositoryRuleConfiguration],
        candidates: T::Array[MetadataSources::Types::Candidate],
      ).returns(T::Hash[RepositoryRuleConfiguration, T::Array[EvaluationResult]])
    end
    def bulk_evaluate_candidates(context, ref_update, rule_configs, candidates)
      evaluation_results_by_rule_config = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[RepositoryRuleConfiguration, T::Array[EvaluationResult]])

      candidates.each do |candidate|
        rule_configs.each do |rule_config|
          T.must(evaluation_results_by_rule_config[rule_config]).push(evaluate_candidate(context, ref_update, rule_config, candidate))
        end
      end

      evaluation_results_by_rule_config
    end

    sig do
      overridable.params(
        context: RuleEvaluationContext,
        ref_update: Git::Ref::Update,
        rule_config: RepositoryRuleConfiguration,
        candidate: MetadataSources::Types::Candidate,
      ).returns(EvaluationResult)
    end
    def evaluate_candidate(context, ref_update, rule_config, candidate)
      raise NotImplementedError
    end

    sig do
      abstract.params(
        context: RuleEvaluationContext,
        ref_update: Git::Ref::Update,
        rule_config: RepositoryRuleConfiguration,
        violations: T::Array[Violation],
      )
      .returns(RuleRun)
    end
    def generate_evaluation_result(context, ref_update, rule_config, violations); end
  end
end
