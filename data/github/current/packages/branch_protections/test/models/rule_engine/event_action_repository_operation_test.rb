# typed: true
# frozen_string_literal: true

require "test_helper"

class EventActionRepositoryOperationTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do
    @user = create(:user)
    @business = create(:business)
    @org = create(:business_plus_organization, name: "org1", admin: @user, business: @business)
    @org_admin = @org.admins.first
    @org_repo = create(:private_repository, owner: @org)

    GitHub.flipper[:member_privilege_rulesets].enable
    GitHub.flipper[:repo_policy_bypass].enable

    @ruleset = create(:repository_ruleset, :targets_all_repos, source: @org, target: "repository")
    @config = create(:repository_rule_configuration, rule_type: "repository_delete", repository_ruleset: @ruleset)
  end

  test "create and retrieve rule suite" do
    event = RuleEngine::Events::RepositoryOperationEvent.new(@org_repo, @user, { delete: nil })
    suite = RuleEngine::RuleSuite.for_event_action(event:, action: T.must(event.event_actions.first))
    suite.save!

    persisted_suites = RuleEngine::RuleSuite.load_by_repository_operation_event(event)
    assert_equal 1, persisted_suites.size
    assert_equal suite, persisted_suites.first
  end

  test "saves rule_suite if persist_results is true" do
    event = RuleEngine::Events::RepositoryOperationEvent.new(@org_repo, @user, { delete: nil }, persist_results: false)
    results = RuleEngine::GenericEvaluator.evaluate_rules(event)
    suite = T.must(results.first)
    refute suite.persisted?

    event = RuleEngine::Events::RepositoryOperationEvent.new(@org_repo, @user, { delete: nil }, persist_results: true)
    results = RuleEngine::GenericEvaluator.evaluate_rules(event)
    suite = T.must(results.first)
    assert suite.persisted?
  end


  test "hash" do
    event = RuleEngine::Events::RepositoryOperationEvent.new(@org_repo, @user, { delete: nil })
    event_action = T.must(event.event_actions.first)
    expected_hash = {
      repository_id: event.repository.id,
      operation: :delete,
      operation_value: nil,
    }
    hash = event_action.instrument_data
    assert_same_hash expected_hash, hash
  end
end
