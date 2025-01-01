# typed: true
# frozen_string_literal: true

require "test_helper"

class ExemptionRequestEmailJobTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @org_admin = create(:user)
    @org = create(:business_plus_organization, name: "org1", admin: @org_admin)

    @team = create(:team, organization: @org, privacy: :closed)
    @team.add_member(@org_admin)

    @org_member = create(:user)
    @org.add_member(@org_member)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@org_member, action: :write)
    @org_repo.add_member(@org_admin, action: :admin)
  end

  setup do
    GitHub.flipper[:push_rulesets].enable
    GitHub.flipper[:push_ruleset_delegated_bypass].enable
  end

  test "send notifications" do
    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    push_ruleset.bypass_actors.create!(
      actor: @team,
    )

    suite = create_suite(ruleset: push_ruleset)
    request = create_request(suite:)

    ExemptionRequestMailer.expects(:push_bypass).with(
      @org_admin,
      request,
      "User has requested bypass for push rules",
      "You are receiving this email because you are an approved bypasser for one of the violated rulesets.",
      "#{T.must(request.repository).permalink}/exemptions/1"
    ).returns(stub(deliver_now: nil))

    ExemptionRequestEmailJob.perform_now(request)
  end

  private

  def create_suite(ruleset: nil)
    push_ruleset = ruleset || create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    config = create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })
    ref_update = create_branch_update(@org_repo, name: "main")
    run = RuleEngine::RuleRun.failure(rule_config: config, ref_update: ref_update, message: "failed")
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: @org_member)
    suite.save!

    suite
  end

  def create_request(suite: nil, request_type: "push_ruleset_bypass")
    suite = suite || create_suite

    request = Exemptions::ExemptionRequest.build(
      number: 1,
      resource_owner: suite,
      requester: @org_member,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type:,
    )
  end
end
