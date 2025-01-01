# typed: true
# frozen_string_literal: true

require "test_helper"

class EventActionRefUpdateTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

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
    enable_feature_flag(:repo_policy_bypass)
  end

  test "create and retrieve rule suite" do
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [], result: :allowed)
    suite.save!

    assert suite.event_action.is_a?(RuleEngine::EventActionRefUpdate)
    assert_equal suite.event_action.repository_id, @repo.id
    assert_equal suite.event_action.ref_name, @ref_update.refname
    assert_equal suite.event_action.before_oid, @ref_update.before_oid
    assert_equal suite.event_action.after_oid, @ref_update.after_oid
    assert_nil suite.event_action.policy_oid
  end

  test "is destroyed when rule_suite is destroyed" do
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [], result: :allowed)
    suite.save!
    event_action = suite.event_action
    assert event_action.is_a?(RuleEngine::EventActionRefUpdate)

    suite.destroy
    assert_nil RuleEngine::EventActionRefUpdate.find_by(id: event_action.id)
  end

  test "destroys rule_suite when event_action is destroyed" do
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [], result: :allowed)
    suite.save!
    event_action = suite.event_action
    event_action.destroy

    assert_nil RuleEngine::RuleSuite.find_by(id: suite.id)
  end

  test "publishes hydro event" do
    run_success = RuleEngine::RuleRun.success(rule_config: create(:repository_rule_configuration), ref_update: @ref_update)
    run_failure = RuleEngine::RuleRun.failure(rule_config: create(:repository_rule_configuration), ref_update: @ref_update, message: "A sad failure")
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [run_success, run_failure], actor: @user)
    suite.save!

    hydro_run_messages = [run_success, run_failure].map do |run|
      ruleset = T.must(run.rule_config&.repository_ruleset)
      hydro_success_message = {
        id: run.id,
        result: run.result,
        message: run.message,
        rule_type: run.rule_type,
        rule_suite_id: run.repository_rule_suite_id,
        rule_configuration_id: run.repository_rule_configuration_id,
        ruleset_id: ruleset.id,
        ruleset_name: ruleset.name,
        ruleset_target: ruleset.target,
        ruleset_source_type: ruleset.source.class.name,
        enforcement: ruleset.enforcement,
        rule_provider: run.rule_provider,
        violations: {}.to_json,
        evaluation_metadata: {}.to_json
      }
    end

    assert_hydro_published({
      repository: Hydro::EntitySerializer.repository(@repo),
      user: Hydro::EntitySerializer.user(@user),
      public_key: nil,
      rule_suite_id: suite.id,
      before_oid: suite.event_action.before_oid,
      after_oid: suite.event_action.after_oid,
      policy_oid: suite.event_action.policy_oid,
      ref_name: suite.event_action.ref_name,
      result: suite.result,
      rule_runs: hydro_run_messages
    }, schema: "github.repositories.v1.RuleSuiteEvaluation")
  end

end
