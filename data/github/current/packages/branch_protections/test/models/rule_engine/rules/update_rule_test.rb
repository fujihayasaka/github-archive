# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo, @user)

    @rule_configs = [
      build(:repository_rule_configuration, rule_type: "update"),
    ]

    @rule = RuleEngine::Rules::UpdateRule.new
  end

  test "fails when ref is being updated" do
    ref_update = create_branch_update(@repo, before_oid: create_random_sha)
    result = @rule.evaluate(@context, ref_update, @rule_configs)
    assert_equal 1, result.size
    assert result.first.failed?
    assert_equal "Cannot update this protected ref.", result.first.message
  end

  test "passes when ref is being updated with fetch_and_merge and update_allows_fetch_and_merge is enabled" do
    @rule_configs[0].parameters["update_allows_fetch_and_merge"] = true
    context = RuleEngine::RuleEvaluationContext.new(@repo, @user, additional_context: { fetch_and_merge: true })

    ref_update = create_branch_update(@repo, before_oid: create_random_sha)
    result = @rule.evaluate(context, ref_update, @rule_configs)
    assert_equal 1, result.size
    assert result.first.allowed?
  end

  test "fails when ref is being updated with fetch_and_merge and update_allows_fetch_and_merge is disabled" do
    context = RuleEngine::RuleEvaluationContext.new(@repo, @user, additional_context: { fetch_and_merge: true })

    ref_update = create_branch_update(@repo, before_oid: create_random_sha)
    result = @rule.evaluate(context, ref_update, @rule_configs)
    assert_equal 1, result.size
    assert result.first.failed?
    assert_equal "Cannot update this protected ref.", result.first.message
  end

  test "is_allow_fork_syncing_param_visible? returns true for forks" do
    org = create :organization, admin: @repo.owner
    forked_repo, reason = @repo.fork(forker: @repo.owner, org: org)
    assert @rule.is_allow_fork_syncing_param_visible?(forked_repo)
  end

  test "is_allow_fork_syncing_param_visible? returns false for non-forks" do
    refute @rule.is_allow_fork_syncing_param_visible?(@repo)
  end
end
