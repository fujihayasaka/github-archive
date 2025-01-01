# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEnginePushesTagNamePatternRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::CandidateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @ref_update = create_tag_update(@repo)
    @rule = T::let(RuleEngine::Rules::TagNamePatternRule.new, RuleEngine::Rules::TagNamePatternRule)
  end

  test "sets appropriate property name, description, and value" do
    assert_equal "tag.name", @rule.property_name
    assert_equal "Tag name", @rule.property_description
    assert_equal "v1.0", @rule.property_value(create_ref_candidate(@ref_update))
  end

  test "only supports ref metadata" do
    assert_equal @rule.supported_metadata_types, [:ref]
  end

  test "skips evaluation when candidate is branch" do
    rule_config = create_rule_config("test", "regex")
    ref_update = create_branch_update(@repo)
    candidate = create_ref_candidate(ref_update)

    assert @rule.evaluate_candidate(@context, ref_update, @rule_config, candidate).success?
  end

  test "skips evaluation when candidate is set for updates" do
    rule_config = create_rule_config("test", "regex")
    ref_update = create_tag_update(@repo, before_oid: "a" * 40)
    candidate = create_ref_candidate(ref_update)

    assert @rule.evaluate_candidate(@context, ref_update, @rule_config, candidate).success?
  end

  test "skips evaluation when candidate is set for deletion" do
    rule_config = create_rule_config("test", "regex")
    ref_update = create_tag_update(@repo, before_oid: "a" * 40, after_oid: GitHub::NULL_OID)
    candidate = create_ref_candidate(ref_update)

    assert @rule.evaluate_candidate(@context, ref_update, @rule_config, candidate).success?
  end

  test "runs evaluation for pattern" do
    rule_config = create_rule_config("^v[0-9]\\.[0-9]$", "regex")
    passing_candidate = create_ref_candidate(@ref_update)

    assert @rule.evaluate_candidate(@context, @ref_update, @rule_config, passing_candidate).success?

    ref_update = create_tag_update(@repo, name: "release-1")
    failed_candidate = create_ref_candidate(ref_update)
    refute @rule.evaluate_candidate(@context, ref_update, @rule_config, failed_candidate).success?
  end

  private

  def create_rule_config(pattern, operator, negate: false)
    @rule_config = build(
      :repository_rule_configuration,
      rule_type: "tag_name_pattern",
      parameters: {
        pattern: pattern,
        operator: operator,
        negate: negate
      }
    )
  end
end
