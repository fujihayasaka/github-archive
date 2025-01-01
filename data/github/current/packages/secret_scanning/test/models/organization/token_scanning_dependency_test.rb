# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgTokenScanningDependencyTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  setup do
    @business = create(:business)
    @admin = create(:user)
    @org = create(:organization)
    @business_org = create(:business_plus_org, admin: @admin, business: @business)
    GitHub.stubs(:configuration_supports_advanced_security?).returns(true)
    @writer = create(:user)
    @business_org.add_member(@writer)

    @security_user = create(:user)
    @business_org.add_member(@security_user)
    grant_custom_org_role(user: @security_user, target: @business_org, fgps: [:org_review_and_manage_secret_scanning_bypass_requests])

    security_manager_team = create(:security_manager_team, organization: @business_org)
    @security_manager = create(:user, login: "securitymanager")
    security_manager_team.add_member(@security_manager)
  end

  test "sets and gets push protection custom message" do
    msg1 = "custom msg1"
    @org.set_push_protection_custom_message(msg1, @admin)
    get1 = @org.get_push_protection_custom_message
    assert_equal msg1, get1

    msg2 = "custom msg2"
    @org.set_push_protection_custom_message(msg2, @admin)
    get2 = @org.get_push_protection_custom_message
    assert_equal msg2, get2
  end

  test "does not inherit message from business" do
    msg1 = "custom msg1"
    @business.set_push_protection_custom_message(msg1, @admin)
    got_msg = @business_org.get_push_protection_custom_message
    assert_nil got_msg
  end

  test "returns own config" do
    msg1 = "custom msg1"
    @business.set_push_protection_custom_message(msg1, @admin)
    msg2 = "custom msg2"
    @business_org.set_push_protection_custom_message(msg2, @admin)
    got_msg = @business_org.get_push_protection_custom_message
    assert_equal msg2, got_msg
  end

  test "returns own config when business does not have one" do
    assert_nil @business.get_push_protection_custom_message
    msg2 = "custom msg2"
    @business_org.set_push_protection_custom_message(msg2, @admin)
    got_msg = @business_org.get_push_protection_custom_message
    assert_equal msg2, got_msg
  end

  context "can_view_delegated_bypass_requests_list?" do
    test "returns false if the user doesn't have the correct FGP" do
      new_user = create(:user)
      @business_org.add_member(new_user)
      refute @business_org.can_view_delegated_bypass_requests_list?(new_user)
    end

    test "returns true" do
      assert @business_org.can_view_delegated_bypass_requests_list?(@security_user)
    end
  end

  context "has_delegated_alert_closure_fgp?" do
    test "returns false if the user doesn't have the correct FGP" do
      new_user = create(:user)
      @business_org.add_member(new_user)
      refute @business_org.has_review_delegated_alert_closure_fgp?(new_user)
    end

    test "returns true for users with the FGP via custom role" do
      new_user = create(:user)
      grant_custom_org_role(user: new_user, target: @business_org, fgps: [:org_review_and_manage_secret_scanning_closure_requests])
      assert @business_org.has_review_delegated_alert_closure_fgp?(new_user)
    end

    test "returns true for users with the FGP via default role" do
      assert @business_org.has_review_delegated_alert_closure_fgp?(@admin)
      assert @business_org.has_review_delegated_alert_closure_fgp?(@security_manager)
    end
  end

  context "token_scanning_bypass_request_count" do
    test "returns count of open, unexpired SS requests" do
      repo1 = create(:private_repository, owner: @business_org)
      repo2 = create(:public_repository, owner: @business_org)

      assert_equal @business_org.token_scanning_bypass_request_count, 0

      rule_suite_1 = RuleEngine::RuleSuite.create!(repository: repo1, ref_name: "refs/heads/main", before_oid: "a" * 40, after_oid: "b" * 40, actor: @writer, owner: repo1.owner)
      rule_suite_2 = RuleEngine::RuleSuite.create!(repository: repo2, ref_name: "refs/heads/main", before_oid: "a" * 40, after_oid: "b" * 40, actor: @writer, owner: repo2.owner)

      # Requests for repo1
      create_exemption_request(rule_suite_1, repo1, "pending", false, SecretScanning::Constants::EXEMPTION_REQUEST_TYPE)
      create_exemption_request(rule_suite_1, repo1, "completed", true, SecretScanning::Constants::EXEMPTION_REQUEST_TYPE)
      approved_request = create_exemption_request(rule_suite_1, repo1, "completed", false, SecretScanning::Constants::EXEMPTION_REQUEST_TYPE)
      Exemptions::ExemptionResponse.approve!(approved_request, @admin)

      # Requests for repo2. Create a lot so as to test pagination.
      (1..20).each do |_i|
        create_exemption_request(rule_suite_2, repo2, "pending", false, SecretScanning::Constants::EXEMPTION_REQUEST_TYPE)
      end
      create_exemption_request(rule_suite_2, repo2, "completed", false, SecretScanning::Constants::EXEMPTION_REQUEST_TYPE)
      rejected_request = create_exemption_request(rule_suite_2, repo2, "completed", false, SecretScanning::Constants::EXEMPTION_REQUEST_TYPE)
      Exemptions::ExemptionResponse.approve!(rejected_request, @admin)

      assert_equal @business_org.token_scanning_bypass_request_count, 21
    end
  end

  context "token_scanning_closure_request_count" do
    test "returns count of open, unexpired alert closure requests" do
      repo1 = create(:private_repository, owner: @business_org)
      repo2 = create(:public_repository, owner: @business_org)

      assert_equal @business_org.token_scanning_closure_request_count, 0

      grant_custom_role(user: @writer, target: repo1, fgps: [:view_secret_scanning_alerts, :resolve_secret_scanning_alerts])
      grant_custom_role(user: @writer, target: repo2, fgps: [:view_secret_scanning_alerts, :resolve_secret_scanning_alerts])

      rule_suite_1 = RuleEngine::RuleSuite.create!(repository: repo1, ref_name: "refs/heads/main", before_oid: "a" * 40, after_oid: "b" * 40, actor: @writer, owner: repo1.owner)
      rule_suite_2 = RuleEngine::RuleSuite.create!(repository: repo2, ref_name: "refs/heads/main", before_oid: "a" * 40, after_oid: "b" * 40, actor: @writer, owner: repo2.owner)

      # Requests for repo1
      create_exemption_request(rule_suite_1, repo1, "pending", false, SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE)
      create_exemption_request(rule_suite_1, repo1, "completed", true, SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE)
      approved_request = create_exemption_request(rule_suite_1, repo1, "completed", false, SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE)
      Exemptions::ExemptionResponse.approve!(approved_request, @admin)

      # Requests for repo2. Create a lot so as to test pagination.
      (1..20).each do |_i|
        create_exemption_request(rule_suite_2, repo2, "pending", false, SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE)
      end
      create_exemption_request(rule_suite_2, repo2, "completed", false, SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE)
      rejected_request = create_exemption_request(rule_suite_2, repo2, "completed", false, SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE)
      Exemptions::ExemptionResponse.approve!(rejected_request, @admin)

      assert_equal @business_org.token_scanning_closure_request_count, 21
    end
  end

  def create_exemption_request(rule_suite, repo, status, expired, request_type)
    expiry = 145.hours.from_now
    if expired
      expiry = 1.hour.ago
    end
    Exemptions::ExemptionRequest.create!(
      resource_owner: rule_suite,
      requester: rule_suite.actor,
      resource_identifier: "ksuid",
      repository: repo,
      request_type: request_type,
      expires_at: expiry,
      metadata: { "reason": "false_positive" },
      requester_comment: "a comment",
      status: status
    )
  end
end
