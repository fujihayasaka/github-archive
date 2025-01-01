# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPolicyRulesetBypassTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include Exemptions::Evaluators

  fixtures do
    @enterprise_owner = create(:user)
    @enterprise = create(:business, owners: [@enterprise_owner])
    @org_admin = create(:user)
    @org = create(:business_plus_organization, admin: @org_admin, business: @enterprise)
    @org_repo = create(:private_repository, owner: @org)
    @user = create(:user)
    @org.add_member(@user)

    enable_feature_flag(:member_privilege_rulesets)
    enable_feature_flag(:repo_policy_bypass)

    @ruleset = create(:repository_ruleset, :targets_all_repos, source: @org, target: "repository")
    @config = create(:repository_rule_configuration, rule_type: "repository_delete", repository_ruleset: @ruleset)
  end

  setup do
    @event = RuleEngine::Events::RepositoryOperationEvent.new(@org_repo, @user, { delete: nil }, persist_results: true)
    @results = RuleEngine::GenericEvaluator.evaluate_rules(@event)
    @rule_suite = T.must(@results.first)
    @request = RepositoryPolicyRulesetBypass.create_request!(@rule_suite, @user, "please let me delete this repo")
  end

  test "event_action is valid" do
    assert @rule_suite.event_action.is_a?(RuleEngine::EventActionRepositoryOperation)
    assert_equal :delete, @rule_suite.event_action.operation
    assert @rule_suite.event_action.persisted?
  end

  test "bypass request is valid" do
    assert @request
    assert @request.valid?
    assert @request.persisted?
    assert_equal "pending", @request.status
    assert_equal "repository_policy_ruleset_bypass", @request.request_type
    assert_equal @rule_suite, @request.resource_owner
    assert_equal @org_repo, @request.repository
    assert_equal @user, @request.requester
    assert_equal "please let me delete this repo", @request.requester_comment
    assert_equal @org_repo.owner_id, @request.owner_id
    assert_equal @org_repo.owner.business.id, @request.business_id
  end

  test "create request url" do
    url = RepositoryPolicyRulesetBypass.create_request_url(@rule_suite)
    # should look something like
    # "https://github.com/testorg-ac399a530d2e/repo-279d3e476f935b07ae8b8fa51a51ea8a/exemptions/new/cmVwb3NpdG9yeV9wb2xpY3lfcnVsZXNldF9ieXBhc3MtMjQ="
    id = Base64.urlsafe_encode64("#{RepositoryPolicyRulesetBypass.request_type}-#{@rule_suite.id}")
    expected_url = UrlHelpers.ruleset_new_bypass_request_url(@org_repo.owner, @org_repo, id, host: GitHub.url)
    assert_equal expected_url, url
  end

  test "existing request" do
    existing = RepositoryPolicyRulesetBypass.existing_request(@rule_suite, @user)
    assert_equal @request, existing
  end
end
