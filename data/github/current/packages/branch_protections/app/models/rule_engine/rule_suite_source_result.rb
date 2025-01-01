# typed: true
# frozen_string_literal: true

module RuleEngine
  # Represents the sub-result of a RuleSuite scoped to a specific source's rules (repo, org)
  class RuleSuiteSourceResult < ApplicationRecord::Repositories
    include GitHub::Memoizer
    include GitHub::BatchMethod
    include Instrumentation::Model

    self.table_name = "repository_rule_suite_source_results"

    belongs_to :rule_suite, class_name: "RuleEngine::RuleSuite", foreign_key: :repository_rule_suite_id, inverse_of: :source_results
    belongs_to :source, polymorphic: true

    RESULTS = RuleSuite::RESULTS.merge({ none: 99 }).with_indifferent_access.freeze
    enum :result, RESULTS, prefix: :result

    EVALUATE_RESULTS = {
      allowed: 0,
      failed: 1,
      bypassed: 3,
      none: 99
    }.with_indifferent_access.freeze
    enum :evaluate_result, EVALUATE_RESULTS, prefix: :evaluate_result

    sig { params(rule_runs: T::Enumerable[RuleRun]).returns(T::Array[RuleSuiteSourceResult]) }
    def self.create_for_runs(rule_runs)
      rule_runs.map do |run|
        # `source` probably shouldn't be ProtectedBranch. But since it is, convert to the repo
        next [run, run.rule_config&.source] unless run.rule_config&.source.is_a?(ProtectedBranch)
        [run, run.rule_config&.source&.repository]
      end.group_by { |_, source| source }.filter_map do |source, runs_and_source|
        next unless source
        runs = runs_and_source.map(&:first)

        result = if runs.reject(&:evaluate_mode?).any?
          if runs.any?(&:failed?)
            runs.filter(&:failed?).all? { |r| r.can_bypass? } ? :bypassed : :failed
          else
            :allowed
          end
        else
          :none
        end
        evaluate_result = if runs.any?(&:evaluate_mode?)
          if runs.any?(&:evaluate_failed?)
            runs.filter(&:evaluate_failed?).all? { |r| r.can_bypass? } ? :bypassed : :failed
          else
            :allowed
          end
        else
          :none
        end

        RuleSuiteSourceResult.new(source:, result:, evaluate_result:)
      end
    end
  end
end
