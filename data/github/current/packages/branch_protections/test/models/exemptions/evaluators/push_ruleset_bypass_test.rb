# typed: true
# frozen_string_literal: true

require "test_helper"

class PushRulesetBypassTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @enterprise_owner = create(:user)
    @enterprise = create(:business, owners: [@enterprise_owner])
    @org_admin = create(:user)
    @org = create(:business_plus_organization, admin: @org_admin, business: @enterprise)
    @org_repo = create(:private_repository, owner: @org)
    @user = create(:user)
    @org.add_member(@user)

    @rule_suite = RuleEngine::RuleSuite.create!(repository: @org_repo, ref_name: "refs/heads/main", before_oid: "before", after_oid: "after", actor: @user)
    @exemption_request = Exemptions::ExemptionRequest.create!(
      resource_owner: @rule_suite,
      requester: @user,
      resource_identifier: "ksuid",
      repository: @org_repo,
      request_type: "push_ruleset_bypass",
      requester_comment: "a comment",
      expires_at: DateTime.now + 1.day,
    )
  end

  setup do
    @evaluator = Exemptions::Evaluators::PushRulesetBypass.new
  end

  context "notification_user_ids" do
    test "returns user ids for org admin" do
      other_user = create(:user)
      @org.add_member(other_user)

      push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
      rule_config = create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
        max_file_path_length: 10
      })
      ref_update = create_branch_update(@org_repo)
      @rule_suite.rule_runs << RuleEngine::RuleRun.failure(rule_config:, ref_update:, message: "message")

      @exemption_request.reload

      assert_equal [@org_admin.id], @evaluator.notification_user_ids(@exemption_request)
    end

    test "returns user ids for enterprise admin" do
      other_user = create(:user)
      @org.add_member(other_user)

      push_ruleset = create(:repository_ruleset, :enterprise_owner_bypass, target: "push", source: @org_repo)
      rule_config = create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
        max_file_path_length: 10
      })
      ref_update = create_branch_update(@org_repo)
      @rule_suite.rule_runs << RuleEngine::RuleRun.failure(rule_config:, ref_update:, message: "message")

      @exemption_request.reload

      assert_equal [@enterprise_owner.id], @evaluator.notification_user_ids(@exemption_request)
    end
  end
end
