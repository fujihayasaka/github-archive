# typed: true
# frozen_string_literal: true

require "test_helper"

class SecretScanningClosureRequestBypassTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  setup do
    @evaluator = Exemptions::Evaluators::SecretScanningClosureRequestBypass.new
    @user = create(:user)
    @org = create(:business_plus_organization)
    @repo_admin = create(:user)
    @repo = create(:repository, owner: @org, admin: @repo_admin)
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

    test "returns false for users without the 'resolve secret scanning alerts' FGP" do
      user_without_fgp = create(:user)
      response, err = @evaluator.is_valid_requester?(@exemption_request, user_without_fgp)
      refute response
      refute_nil err
    end

    test "returns true" do
      # Repo admins have the 'resolve secret scanning alerts' FGP
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

    test "returns false for users without the delegated alert closure FGP" do
      user_without_fgp = create(:user)
      refute @evaluator.is_valid_reviewer?(@exemption_request, user_without_fgp)
    end

    test "returns true" do
      user_with_fgp = create(:user)
      grant_custom_org_role(user: user_with_fgp, target: @org, fgps: [:org_review_and_manage_secret_scanning_closure_requests])
      assert @evaluator.is_valid_reviewer?(@exemption_request, user_with_fgp)
    end
  end



end
