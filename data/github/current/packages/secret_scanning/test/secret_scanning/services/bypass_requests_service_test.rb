# typed: true
# frozen_string_literal: true

require "test_helper"

class BypassRequestsServiceTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @org = create(:business_plus_org, admin: @user)
    @repo = create(:private_repository, owner: @org)

    @reviewer = create(:user)
    @second_reviewer = create(:user)
    @org.add_member(@reviewer, action: :read)
    @org.add_member(@second_reviewer)
    @repo.add_member(@reviewer, action: :read) # Set to :read to test least permissions
    @repo.add_member(@second_reviewer, action: :write)
    @review_team = create(:team, organization: @org, privacy: :closed)
    @review_team.add_member(@reviewer)
    @review_team.add_member(@second_reviewer)
  end

  setup do
    GitHub::TokenScanning::Service::Client.any_instance
      .stubs(:get_bypass_reviewers)
      .with({ repository_id: @repo.id })
      .returns(Twirp::ClientResp.new(
        data: GitHub::Proto::SecretScanning::Scans::V2::GetBypassReviewersResponse.new(
          bypass_reviewers: [
            GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(
              reviewer_id: @review_team.id,
              reviewer_type: :TEAM,
            ),
          ],
        ),
      ))

    @rule_suite = RuleEngine::RuleSuite.create!(repository: @repo, ref_name: "refs/heads/main", before_oid: "a" * 40, after_oid: "b" * 40, actor: @second_reviewer)
    @exemption_request = create_exemption_request(@rule_suite, @second_reviewer, "ksuid123", @repo)
  end

  context "#review_exemption_request!" do
    test "fails with invalid status" do
      res, fail_reason = ::SecretScanning::Services::BypassRequestsService.review_exemption_request!(
        exemption_request: @exemption_request,
        status: "asdf",
        message: "msg",
        user: @reviewer,
        repo: @repo,
      )
      assert_nil res
      assert_equal "Invalid status: asdf", fail_reason
    end

    test "approves" do
      res, fail_reason = ::SecretScanning::Services::BypassRequestsService.review_exemption_request!(
        exemption_request: @exemption_request,
        status: "approve",
        message: "msg",
        user: @reviewer,
        repo: @repo,
      )
      assert_nil fail_reason
      assert_equal "approved", res&.status
      assert_equal "approved", @exemption_request.reload.status
    end

    test "rejects" do
      res, fail_reason = ::SecretScanning::Services::BypassRequestsService.review_exemption_request!(
        exemption_request: @exemption_request,
        status: "reject",
        message: "msg",
        user: @reviewer,
        repo: @repo,
      )
      assert_nil fail_reason
      assert_equal "rejected", res&.status
    end
  end

  context "#validate_request_message" do
    test "fails if nil message" do
      success, fail_reason = ::SecretScanning::Services::BypassRequestsService.validate_request_message(nil)
      refute success
      assert_equal "Message is required", fail_reason
    end

    test "fails if empty message" do
      success, fail_reason = ::SecretScanning::Services::BypassRequestsService.validate_request_message("")
      refute success
      assert_equal "Message is required", fail_reason
    end

    test "fails if whitespace message" do
      success, fail_reason = ::SecretScanning::Services::BypassRequestsService.validate_request_message("    ")
      refute success
      assert_equal "Message is required", fail_reason
    end

    test "fails if message is too long" do
      success, fail_reason = ::SecretScanning::Services::BypassRequestsService.validate_request_message("asdf#{"a" * SecretScanning::Services::BypassRequestsService::MSG_LIMIT}")
      refute success
      assert_equal "Message exceeds #{SecretScanning::Services::BypassRequestsService::MSG_LIMIT} character limit", fail_reason
    end

    test "succeeds" do
      success, fail_reason = ::SecretScanning::Services::BypassRequestsService.validate_request_message("msg")
      assert success
      assert_nil fail_reason
    end
  end

  private

  def create_exemption_request(rule_suite, user, resource_id, repo)
    Exemptions::ExemptionRequest.create!(
      resource_owner: rule_suite,
      requester: user,
      resource_identifier: resource_id,
      repository: repo,
      request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
      expires_at: 145.hours.from_now,
      metadata: { "reason": "false_positive" },
      requester_comment: "a comment"
    )
  end
end
