# typed: true
# frozen_string_literal: true

require "test_helper"

module RuleEngine
  class RuleSuiteSourceResultTest < GitHub::TestCase
    include RulesEngine::RefUpdateTestHelper

    fixtures do
      @repo = create(:repository)
      @user = create(:user)
      @repo.add_member @user, action: :write

      @org = create(:organization, plan: "business_plus")
      @org_admin = @org.admins.first
      @org_repo = create(:private_repository, owner: @org)
    end

    setup do
      @ref_update = create_branch_update(@repo)
      @org_ref_update = create_branch_update(@org_repo)
    end

    test "copies repository id from source result" do
      enable_feature_flag(:set_repository_id_from_rule_suite_on_source_result)
      rs1 = create(:repository_ruleset, :with_rules, source: @org_repo)
      rs2 = create(:repository_ruleset, :with_rules, source: @org_repo)

      run1 = RuleEngine::RuleRun.success(rule_config: rs1.rule_configurations.first, ref_update: @org_ref_update)
      run2 = RuleEngine::RuleRun.failure(rule_config: rs2.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1, run2], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert_equal suite.repository_id, @org_repo.id
      assert_equal suite.event_action.repository_id, @org_repo.id

      suite.source_results.each do |source_result|
        assert_equal @org_repo.id, source_result.repository_id
      end
    end

    test "rule_suite presence is required" do
      enable_feature_flag(:require_rule_suite_on_source_result)

      suite_source_result = RuleSuiteSourceResult.new(rule_suite: nil)
      refute_valid suite_source_result
      assert_includes suite_source_result.errors[:rule_suite], "can't be blank"
    end
  end
end
