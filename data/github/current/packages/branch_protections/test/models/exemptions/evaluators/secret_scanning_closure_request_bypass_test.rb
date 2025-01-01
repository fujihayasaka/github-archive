# typed: true
# frozen_string_literal: true

require "test_helper"

class SecretScanningClosureRequestBypassTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  setup do
    @evaluator = Exemptions::Evaluators::SecretScanningClosureRequestBypass.new
    @user = create(:user)
    @org_admin = create(:user)
    @org = create(:business_plus_organization, admin: @org_admin)
    @repo_admin = create(:user)
    @repo = create(:private_repository, owner: @org, admin: @repo_admin)
    @repo.add_member(@user)
    @exemption_request = Exemptions::ExemptionRequest.create(
      requester: @user,
      resource_identifier: "ksuid",
      resource_owner: @repo,
      repository: @repo,
      request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
      requester_comment: "a comment",
      expires_at: DateTime.now + 1.day,
    )
  end

  context "evaluate" do
    test "evaluate returns EvaluationResult::Pending if there are no responses" do
      assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Pending, @evaluator.evaluate(@exemption_request, [])
    end

    test "evaluate returns the status of the most recent response" do
      reviewer = create(:user)
      approved_response = Exemptions::ExemptionResponse.new(
        exemption_request: @exemption_request,
        reviewer: reviewer,
        status: Exemptions::ExemptionResponse::STATUSES[:approved]
      )
      rejected_response = Exemptions::ExemptionResponse.new(
        exemption_request: @exemption_request,
        reviewer: reviewer,
        status: Exemptions::ExemptionResponse::STATUSES[:rejected]
      )

      assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Approved, @evaluator.evaluate(@exemption_request, [rejected_response, approved_response])
      assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Rejected, @evaluator.evaluate(@exemption_request, [approved_response, rejected_response])
    end
  end

  context "is_valid_requester?" do
    test "returns false for PublicKeys" do
      key = create(:public_key, repository: @repo)
      response, err = @evaluator.is_valid_requester?(@exemption_request, key)
      refute response
      refute_nil err
    end

    test "returns false for users without read permissions on the repo" do
      user_without_read_perms = create(:user)
      response, err = @evaluator.is_valid_requester?(@exemption_request, user_without_read_perms)
      refute response
      refute_nil err
    end

    test "returns true" do
      # Repo admins have both read perms as well as the 'resolve secret scanning alerts' FGP
      response, err = @evaluator.is_valid_requester?(@exemption_request, @repo_admin)
      assert response
      assert_nil err
    end
  end

  context "is_valid_reviewer?" do
    test "returns false for the user that submitted the request" do
      refute @evaluator.is_valid_reviewer?(@exemption_request, @user)
    end

    test "returns false for PublicKeys" do
      key = create(:public_key, repository: @repo)
      refute @evaluator.is_valid_reviewer?(@exemption_request, key)
    end

    test "returns false for users without read permissions on the repo" do
      user_without_read_perms = create(:user)
      refute @evaluator.is_valid_reviewer?(@exemption_request, user_without_read_perms)
    end

    test "returns false for users without the delegated alert closure FGP" do
      user_without_fgp = create(:user)
      @repo.add_member(user_without_fgp)
      refute @evaluator.is_valid_reviewer?(@exemption_request, user_without_fgp)
    end

    test "returns true" do
      user_with_fgp = create(:user)
      @repo.add_member(user_with_fgp)
      grant_custom_org_role(user: user_with_fgp, target: @org, fgps: [:org_review_and_manage_secret_scanning_closure_requests])
      assert @evaluator.is_valid_reviewer?(@exemption_request, user_with_fgp)
    end
  end

  test "notification_user_ids returns user ids for org admins, security managers, and users with the FGP" do
    @security_manager = create(:user, name: "org-security-manager")
    @org.add_member(@security_manager)
    @security_manager_team = create(:security_manager_team, organization: @org)
    @security_manager_team.add_member(@security_manager)

    other_user = create(:user)
    @org.add_member(other_user)

    fgp = :org_review_and_manage_secret_scanning_closure_requests
    fgp_user_1 = create(:user)
    @org.add_member(fgp_user_1)
    grant_custom_org_role(user: fgp_user_1, target: @org, fgps: [fgp], base_role: Role.write_role)
    fgp_user_2 = create(:user)
    @org.add_member(fgp_user_2)
    team = create(:team, organization: @org, privacy: :closed)
    team.add_member(fgp_user_2)
    grant_custom_org_role(user: team, target: @org, fgps: [fgp], base_role: Role.maintain_role)

    user_ids_to_notify = @evaluator.notification_user_ids(@exemption_request)
    assert_same_elements [@security_manager.id, @org_admin.id, fgp_user_1.id, fgp_user_2.id], user_ids_to_notify
  end
end
