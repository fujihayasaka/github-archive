# typed: true
# frozen_string_literal: true

require "test_helper"

# A matrix test of the different combinations of rule statuses and evaluate statuses for `fetch_rule_suites`
class RuleEngineRuleSettingsDependencyInsightsTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @fetch_suites_enterprise = create(:business)
    @fetch_suites_org = create(:business_plus_org, admin: @org_admin, business: @fetch_suites_enterprise)
    @fetch_suites_repo = create(:repository, owner: @fetch_suites_org)
    @insights_cases = generate_insights_cases
  end

  %w[pass fail bypass all].each do |rule_status|
    %w[all active evaluate].each do |evaluate_status|
      test "matrix test: rule_status:#{rule_status}, evaluate_status:#{evaluate_status}" do
        expected, unexpected = insights_case_generator(rule_status:, evaluate_status:)

        suites, _ = @fetch_suites_repo.fetch_rule_suites(rule_status:, evaluate_status:, page_size: expected.size + unexpected.size)

        extras = unexpected.filter { |suite, _| suites.include?(suite) }
        missing = expected.reject { |suite, _| suites.include?(suite) }
        message = ""
        if extras.any?
          message += "\nQuery matched suites that were unexpected (looking for #{rule_status}-#{evaluate_status})\n"
          message += extras.map do |suite, matches|
            "  - Suite ##{suite.id} should only match #{matches}"
          end.join("\n")
        end
        if missing.any?
          message += "\nQuery did not match suites that were expected (looking for #{rule_status}-#{evaluate_status})\n"
          message += missing.map do |suite, matches|
            "  - Suite ##{suite.id} should match #{matches}"
          end.join("\n")
        end

        assert_equal expected.size, suites.size, message
        assert_same_elements expected.keys.map(&:id), suites.map(&:id), message
      end
    end
  end

  sig { returns(T::Hash[RuleEngine::RuleSuite, T::Array[String]]) }
  def generate_insights_cases
    {
      create_rule_suite(runs: [{ result: "allowed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: false }]) => %w[pass-active pass-all].freeze,
      create_rule_suite(runs: [{ result: "allowed", source: @fetch_suites_org, evaluate_mode: false, can_bypass: false }]) => %w[pass-active pass-all].freeze,
      create_rule_suite(runs: [{ result: "allowed", source: @fetch_suites_enterprise, evaluate_mode: false, can_bypass: false }]) => %w[pass-active pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_org, evaluate_mode: false, can_bypass: false },
        { result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false },
      ]) => %w[pass-active pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: false },
        { result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false },
      ]) => %w[pass-active pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_org, evaluate_mode: false, can_bypass: false },
        { result: "allowed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false }
      ]) => %w[ pass-active pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: false },
        { result: "allowed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false }
      ]) => %w[pass-active pass-evaluate pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false },
        { result: "allowed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false }
      ]) => %w[pass-evaluate pass-all].freeze,
      create_rule_suite(runs: [{ result: "allowed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false }]) => %w[pass-evaluate pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false },
        { result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false },
      ]) => %w[pass-evaluate pass-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: false }]) => %w[fail-active fail-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_org, evaluate_mode: false, can_bypass: false }]) => %w[fail-active fail-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_enterprise, evaluate_mode: false, can_bypass: false }]) => %w[fail-active fail-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false }]) => %w[fail-evaluate fail-all].freeze,
      create_rule_suite(runs: [
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false },
        { result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false },
      ]) => %w[fail-evaluate fail-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: true }]) => %w[bypass-active bypass-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_org, evaluate_mode: false, can_bypass: true }]) => %w[bypass-active bypass-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_enterprise, evaluate_mode: false, can_bypass: true }]) => %w[bypass-active bypass-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: true }]) => %w[bypass-evaluate bypass-all].freeze,
      create_rule_suite(runs: [
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: true },
        { result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: true },
      ]) => %w[bypass-evaluate bypass-all].freeze,
      create_rule_suite(runs: [
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: false },
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: true },
      ]) => %w[bypass-evaluate fail-active fail-all].freeze,
      create_rule_suite(runs: [
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: true },
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: true },
      ]) => %w[bypass-active bypass-evaluate bypass-all].freeze,
      create_rule_suite(runs: [{ result: "allowed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false }]) => [].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: true }]) => [].freeze,
      create_rule_suite(runs: [{ result: "allowed", source: @fetch_suites_enterprise, evaluate_mode: true, can_bypass: false }]) => [].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_enterprise, evaluate_mode: true, can_bypass: true }]) => [].freeze,
    }.freeze
  end

  sig do
    params(rule_status: String, evaluate_status: String)
    .returns([T::Hash[RuleEngine::RuleSuite, T::Array[String]], T::Hash[RuleEngine::RuleSuite, T::Array[String]]])
  end
  def insights_case_generator(rule_status:, evaluate_status:)
    expected = @insights_cases.filter do |_, matches|
      next true if matches.include?("#{rule_status}-#{evaluate_status}")
      next true if rule_status == "all" && matches.any? { |match| match.ends_with?("-#{evaluate_status}") }
      false
    end
    unexpected = @insights_cases.reject { |case_match| expected.include?(case_match) }

    [expected, unexpected]
  end

  sig do
    params(
      runs: T::Array[{
        source: RuleEngine::Types::RuleSource,
        result: String,
        evaluate_mode: T::Boolean,
        can_bypass: T::Boolean,
      }],
    ).returns(RuleEngine::RuleSuite)
  end
  def create_rule_suite(runs:)
    ref_update = create_branch_update(@fetch_suites_repo)

    rule_runs = runs.map do |run|
      ruleset = create(:repository_ruleset, :example_ruleset, source: run[:source])
      ruleset.update!(enforcement: :evaluate) if run[:evaluate_mode]

      run = if run[:result] == "allowed"
        RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update)
      else
        RuleEngine::RuleRun.failure(rule_config: ruleset.rule_configurations.first, ref_update: ref_update, message: "fail")
      end
    end

    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs:, actor: @org_admin)
    suite.result = :bypassed if runs.any? { !_1[:evaluate_mode] } && runs.filter { !_1[:evaluate_mode] }.all? { _1[:can_bypass] }
    suite.save

    suite.source_results.each do |source_result|
      filtered_runs = runs.filter { |run| source_result.source == run[:source] }
      source_result.result = :bypassed if filtered_runs.any? { !_1[:evaluate_mode] } && filtered_runs.filter { !_1[:evaluate_mode] }.all? { _1[:can_bypass] }
      source_result.evaluate_result = :bypassed if filtered_runs.any? { _1[:evaluate_mode] } && filtered_runs.filter { _1[:evaluate_mode] }.all? { _1[:can_bypass] }
      source_result.save
    end

    suite
  end
end
