# typed: true
# frozen_string_literal: true

require "test_helper"

class SecretScanningBypassTest < GitHub::TestCase

  setup do
    @evaluator = Exemptions::Evaluators::SecretScanningBypass.new
    @user = create(:user)
    @org = create(:business_plus_organization)
    @repo = create(:repository, owner: @org)
    SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
    resource_owner = RuleEngine::RuleSuite.create!(repository: @repo, ref_name: "refs/heads/main", before_oid: "before", after_oid: "after", actor: @user)
    @exemption_request = Exemptions::ExemptionRequest.create!(
      resource_owner: resource_owner,
      requester: @user,
      resource_identifier: "ksuid",
      repository: @repo,
      request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
      requester_comment: "a comment",
      expires_at: DateTime.now + 1.day,
    )
  end

  context "is_valid_requester?" do
    test "returns true for the user that initiated the push" do
      assert @evaluator.is_valid_requester?(@exemption_request, @user)
    end

    test "returns false for other users" do
      different_user = create(:user)
      assert @evaluator.is_valid_requester?(@exemption_request, different_user)
    end
  end
  context "is_valid_reviewer?" do
    test "method successfully calls service method" do
      reviewer_user = create(:user)
      reviewers = [
        stub(reviewer_id: reviewer_user.id, reviewer_type: :USER),
      ]
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([reviewers, nil]).times(1)
      @evaluator.is_valid_reviewer?(@exemption_request, reviewer_user)
    end

    test "returns false if the requester is the reviewer" do
      refute @evaluator.is_valid_reviewer?(@exemption_request, @user)
    end
  end

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

  context "notification_user_ids" do
    test "repo-enabled: determines default roles + custom role + team + org admins users to notify" do
      team = create(:team, organization: @org)
      team_user = create(:user)
      team.add_member(team_user)
      org_admin_user = create(:user)
      @org.add_admin(org_admin_user)

      custom_role_user = create(:user)
      custom_repo_role = create(:custom_repository_role, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)
      user_role = create(:user_role, actor: custom_role_user, role: custom_repo_role, target: @repo)
      repo_admin_user = create(:user)
      @repo.add_member(repo_admin_user, action: :admin)
      repo_admin_role = T.must(RepositoryRole.find_by(name: "admin"))
      assert @repo.adminable_by?(repo_admin_user)

      repo_maintain_user = create(:user)
      @repo.add_member(repo_maintain_user, action: :maintain)
      repo_maintain_role = T.must(RepositoryRole.find_by(name: "maintain"))

      reviewers = [
        stub(reviewer_id: team.id, reviewer_type: :TEAM),
        stub(reviewer_id: 1, reviewer_type: :ORG_ADMIN),
        stub(reviewer_id: repo_maintain_role.id, reviewer_type: :ROLE),
        stub(reviewer_id: repo_admin_role.id, reviewer_type: :ROLE),
        stub(reviewer_id: user_role.role_id, reviewer_type: :ROLE),
      ]
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers)
        .with(@repo, @user.id)
        .returns([reviewers, nil])
        .once

      expected_user_ids = [
        team_user.id,
        custom_role_user.id,
        repo_maintain_user.id,
        repo_admin_user.id,
        *@org.admin_ids,
      ].uniq

      user_ids_to_notify = @evaluator.notification_user_ids(@exemption_request)
      assert_same_elements expected_user_ids, user_ids_to_notify
    end

    test "org-enabled: determines default roles + custom role + team + org admins users to notify" do
      SecretScanning::Features::Repo::DelegatedBypass.any_instance.stubs(:enabled_by_organization?).returns(true)
      team = create(:team, organization: @org)
      team_user = create(:user)
      team.add_member(team_user)
      org_admin_user = create(:user)
      @org.add_admin(org_admin_user)

      custom_role_user = create(:user)
      custom_repo_role = create(:custom_repository_role, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)
      user_role = create(:user_role, actor: custom_role_user, role: custom_repo_role, target: @repo)
      repo_admin_user = create(:user)
      @repo.add_member(repo_admin_user, action: :admin)
      repo_admin_role = T.must(RepositoryRole.find_by(name: "admin"))
      assert @repo.adminable_by?(repo_admin_user)

      repo_maintain_user = create(:user)
      @repo.add_member(repo_maintain_user, action: :maintain)
      repo_maintain_role = T.must(RepositoryRole.find_by(name: "maintain"))

      reviewers = [
        stub(reviewer_id: team.id, reviewer_type: :TEAM),
        stub(reviewer_id: 1, reviewer_type: :ORG_ADMIN),
        stub(reviewer_id: repo_maintain_role.id, reviewer_type: :ROLE),
        stub(reviewer_id: repo_admin_role.id, reviewer_type: :ROLE),
        stub(reviewer_id: user_role.role_id, reviewer_type: :ROLE),
      ]
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers)
        .with(@repo, @user.id)
        .returns([reviewers, nil])
        .once

      expected_user_ids = [
        team_user.id,
        custom_role_user.id,
        repo_maintain_user.id,
        repo_admin_user.id,
        *@org.admin_ids,
      ].uniq

      user_ids_to_notify = @evaluator.notification_user_ids(@exemption_request)
      assert_same_elements expected_user_ids, user_ids_to_notify
    end
  end
end
