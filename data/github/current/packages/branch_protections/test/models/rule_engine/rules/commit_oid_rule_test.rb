# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEnginePushesCommitOidRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::CandidateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @ref_update = create_branch_update(@repo)
    @rule = T::let(RuleEngine::Rules::CommitOidRule.new, RuleEngine::Rules::CommitOidRule)
  end

  test "succeeds when commit oid does not match" do
    candidate = create_commit_candidate
    rule_config = create_rule_config
    assert @rule.evaluate_candidate(@context, @ref_update, rule_config, candidate).success?
  end

  test "fails when commit oid matches" do
    candidate = create_commit_candidate(id: @ref_update.after_oid)
    rule_config = create_rule_config(commit_oids: [@ref_update.after_oid])
    refute @rule.evaluate_candidate(@context, @ref_update, rule_config, candidate).success?
  end

  test "generates allowed rule run when no violations" do
    rule_config = create_rule_config
    result = @rule.generate_evaluation_result(@context, @ref_update, rule_config, [])
    assert_predicate result, :allowed?
  end

  test "generates failed rule run when violations exist" do
    violations = [RuleEngine::Violation.new(candidate: create_commit_candidate)]
    rule_config = create_rule_config
    result = @rule.generate_evaluation_result(@context, @ref_update, rule_config, violations)

    assert_predicate result, :failed?
  end

  private

  def create_rule_config(commit_oids: [SecureRandom.hex(20)])
    @rule_config = build(
      :repository_rule_configuration,
      rule_type: "commit_oid",
      parameters: {
        "restricted_commits" => commit_oids.map { |commit_oid| { "oid" => commit_oid } }
      }
    )
  end
end
