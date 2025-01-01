# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleRunTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @repo = create(:repository)
    @user = create(:user)
    @repo.add_member @user, action: :write
  end

  setup do
    @ref_update = create_branch_update(@repo)
  end

  test "create allowed rule run" do
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update)
    rule_config = create(:repository_rule_configuration)
    run = RuleEngine::RuleRun.success(rule_config: rule_config, ref_update: @ref_update)
    run.rule_suite = suite
    run.save!

    persisted_run = RuleEngine::RuleRun.find_by(rule_suite: suite, rule_config: rule_config)
    refute persisted_run.nil?
    assert_equal run, persisted_run
    assert T.must(persisted_run).allowed?
  end

  test "create failure rule run" do
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update)
    rule_config = create(:repository_rule_configuration)
    run = RuleEngine::RuleRun.failure(rule_config: rule_config, ref_update: @ref_update, message: "failure")
    run.rule_suite = suite
    run.save!

    persisted_run = RuleEngine::RuleRun.find_by(rule_suite: suite, rule_config: rule_config)
    refute persisted_run.nil?
    assert_equal run, persisted_run
    assert T.must(persisted_run).failed?
  end

  test "message truncates over 1024 characters and reports to failbot" do
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update)
    rule_config = create(:repository_rule_configuration)
    run = RuleEngine::RuleRun.failure(rule_config: rule_config, ref_update: @ref_update, message: "a" * 1025)
    run.rule_suite = suite
    run.save!

    assert_equal 1024, run.message&.length
    assert run.message&.end_with?(RuleEngine::RuleRun::TRUNCATED_MESSAGE)
  end
end
