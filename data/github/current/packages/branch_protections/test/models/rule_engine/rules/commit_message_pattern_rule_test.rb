# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEnginePushesCommitMessagePatternRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::CandidateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @ref_update = create_branch_update(@repo)
    @rule = T::let(RuleEngine::Rules::CommitMessagePatternRule.new, RuleEngine::Rules::CommitMessagePatternRule)
  end

  test "sets appropriate property name, description, and value" do
    assert_equal "commit.message", @rule.property_name
    assert_equal "Commit message", @rule.property_description
    assert_equal "Initial commit", @rule.property_value(create_commit_candidate)
  end

  test "only supports commit metadata" do
    assert_equal @rule.supported_metadata_types, [:commit]
  end

  test "runs evaluation for pattern" do
    rule_config = create_rule_config("^Initial commit$", "regex")
    passing_candidate = create_commit_candidate

    assert @rule.evaluate_candidate(@context, @ref_update, @rule_config, passing_candidate).success?

    failing_candidate = create_commit_candidate(message: "Bug fix")
    refute @rule.evaluate_candidate(@context, @ref_update, @rule_config, failing_candidate).success?
  end

  private

  def create_rule_config(pattern, operator, negate: false)
    @rule_config = build(
      :repository_rule_configuration,
      rule_type: "commit_message_pattern",
      parameters: {
        pattern: pattern,
        operator: operator,
        negate: negate
      }
    )
  end
end
