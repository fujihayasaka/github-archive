# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEnginePushesMetadataPatternRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::CandidateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @ref_update = create_branch_update(@repo)
    @rule = T::let(TestCommitMessagePatternRule.new, TestCommitMessagePatternRule)
  end

  test "skips evaluation when candidate is set for deletion" do
    rule_config = create_rule_config("test", "regex")
    ref_update = create_branch_update(@repo, before_oid: create_random_sha, after_oid: GitHub::NULL_OID)
    candidate = create_commit_candidate

    assert @rule.evaluate_candidate(@context, ref_update, @rule_config, candidate).success?
  end

  pattern_inputs = [
    ["regex", "^Test$"],
    %w[starts_with Te],
    %w[ends_with st],
    %w[contains es],
  ]

  pattern_inputs.each do |operator, pattern|
    test "only succeeds when property matches #{operator} pattern" do
      rule_config = create_rule_config(pattern, operator)

      passing_candidate = create_commit_candidate(message: "Test")
      assert @rule.evaluate_candidate(@context, @ref_update, @rule_config, passing_candidate).success?, "Rule should succeed when property matches #{operator} pattern"

      failing_candidate = create_commit_candidate(message: "Failing")
      refute @rule.evaluate_candidate(@context, @ref_update, @rule_config, failing_candidate).success?, "Rule should not succeed when property does match #{operator} pattern"
    end
  end

  test "allows negation of pattern match" do
    rule_config = create_rule_config("est", "ends_with", negate: true)

    candidate = create_commit_candidate(message: "Test")

    refute @rule.evaluate_candidate(@context, @ref_update, rule_config, candidate).success?
  end

  test "validates property, operator, negate, and pattern parameters" do
    @rule_config = build(:repository_rule_configuration, rule_type: "commit_message_pattern", parameters: {})
    assert @rule.validate_parameterized(@rule_config).any?

    @rule_config.parameters = { operator: "regex" }
    assert @rule.validate_parameterized(@rule_config).any?

    @rule_config.parameters = { operator: "regex", pattern: ".*" }
    assert @rule.validate_parameterized(@rule_config).empty?

    @rule_config.parameters = { operator: "regex", pattern: ".*", negate: nil }
    assert @rule.validate_parameterized(@rule_config).empty?

    @rule_config.parameters = { operator: "regex", pattern: ".*", negate: true }
    assert @rule.validate_parameterized(@rule_config).empty?
  end

  test "validates regex patterns" do
    @rule_config = build(:repository_rule_configuration, rule_type: "commit_message_pattern", parameters: { operator: "regex", pattern: ".*" })
    assert @rule.validate_parameterized(@rule_config).empty?

    @rule_config.parameters = { operator: "regex", pattern: "**/*" }
    assert @rule.validate_parameterized(@rule_config).any?
  end

  test "generates failed run with property description for pattern" do
    violations = [
      RuleEngine::Violation.new(candidate: create_commit_candidate(message: "test")),
    ]

    rule_config = create_rule_config("1", "starts_with")

    result = @rule.generate_evaluation_result(@context, @ref_update, rule_config, violations)

    assert_equal "Test must start with a matching pattern: 1", result.message
    assert_predicate result, :failed?
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

  class TestCommitMessagePatternRule < RuleEngine::MetadataPatternRule
    def initialize
      super(rule_name: "commit_message_pattern", display_name: "Restrict commit messages")
    end

    def supported_metadata_types
      [:commit]
    end

    def property_name
      "test"
    end

    def property_description
      "Test"
    end

    def property_value(candidate)
      candidate.message
    end
  end
end
