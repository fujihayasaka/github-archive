# typed: true
# frozen_string_literal: true

require "test_helper"

class CreationRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo, @user)

    @rule_configs = [
      build(:repository_rule_configuration, rule_type: "creation"),
    ]

    @rule = RuleEngine::Rules::CreationRule.new
  end

  test "fails when ref is being created" do
    ref_update = create_branch_update(@repo)
    result = @rule.evaluate(@context, ref_update, @rule_configs)
    assert_equal 1, result.size
    assert result.first.failed?
    assert_equal "Cannot create ref due to create name restrictions.", result.first.message
  end

  test "passes when ref is being updated" do
    ref_update = create_branch_update(@repo, before_oid: create_random_sha)
    result = @rule.evaluate(@context, ref_update, @rule_configs)
    assert_equal 1, result.size
    assert result.first.allowed?
  end

  test "passes when ref is being deleted" do
    ref_update = create_branch_update(@repo, before_oid: create_random_sha, after_oid: GitHub::NULL_OID)
    result = @rule.evaluate(@context, ref_update, @rule_configs)
    assert_equal 1, result.size
    assert result.first.allowed?
  end
end
