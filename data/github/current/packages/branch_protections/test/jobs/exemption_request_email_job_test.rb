# typed: true
# frozen_string_literal: true

require "test_helper"

class ExemptionRequestEmailJobTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @org_admin = create(:user)
    @org = create(:business_plus_organization, name: "org1", admin: @org_admin)

    @team = create(:team, organization: @org, privacy: :closed)
    ::SecurityProduct::SecurityManagerRole.grant_to_team!(@team)
    @team.add_member(@org_admin)

    @org_member = create(:user)
    @org.add_member(@org_member)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@org_member, action: :write)
    @org_repo.add_member(@org_admin, action: :admin)
  end

  context "send notifications" do
    test "send notifications for push bypass" do
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

    test "send notifications for code scanning alert dismissal requests" do
      request = build_code_scanning_alert_dismissal_request(@org_repo)

      ExemptionRequestMailer.expects(:alert_dismissal_requested).with(
        @org_admin,
        request,
        "Request to dismiss a code scanning alert",
        "You are receiving this email because you are an approved reviewer for code scanning alert dismissal.",
        "#{GitHub.url}/#{@org_repo.name_with_display_owner}/security/code-scanning/#{request.metadata["alert_number"]}"
      ).returns(stub(deliver_now: nil))

      ExemptionRequestEmailJob.perform_now(request)
    end

    test "send notifications for secret scanning alert dismissal requests" do
      request = build_secret_scanning_alert_dismissal_request(@org_repo)

      ExemptionRequestMailer.expects(:alert_dismissal_requested).with(
        @org_admin,
        request,
        "Request to dismiss a secret scanning alert",
        "You are receiving this email because you are an approved reviewer for secret scanning alert dismissal.",
        "#{GitHub.url}/#{@org_repo.name_with_display_owner}/security/secret-scanning/#{request.resource_identifier}"
      ).returns(stub(deliver_now: nil))

      ExemptionRequestEmailJob.perform_now(request)
    end
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

  def build_code_scanning_alert_dismissal_request(repo)
    Exemptions::ExemptionRequest.build(
      number: 1,
      requester: @requester,
      repository: repo,
      request_type: CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE,
      resource_owner: repo,
      metadata: {
        "resolution": Turboscan::Proto::ResultResolution::WONT_FIX.to_s,
        "alert_number": 1,
        "alert_title": "XSS Vulnerability",
      },
      requester_comment: "wont fix",
      created_at: Time.now,
    )
  end

  def build_secret_scanning_alert_dismissal_request(repo)
    Exemptions::ExemptionRequest.build(
      number: 1,
      requester: @requester,
      repository: repo,
      request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
      resource_owner: repo,
      metadata: {
        "reason": "fixed_later",
        "alert_title": "GitHub Secret Scanning",
      },
      requester_comment: "wont fix",
      created_at: Time.now,
    )
  end
end
