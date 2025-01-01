# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RemoveUserFromRepoCleanupJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @member = create(:user)
    @admin = create(:user)
    @business = create(:business)
    @org = create(:organization, admin: @admin, business: @business)
    @org.add_member(@member)
    @repo = create(:private_repository, owner: @org)
    @repo.add_member(@member, action: :write)
    @outside_collaborator = create(:user)
    @repo.add_member(@outside_collaborator, action: :write)
  end

  test "peforms all the work to disassociate a user from a repo when they're fully removed" do
    Repository.any_instance.expects(:cancel_all_invitations_from_user).with(@outside_collaborator, @admin)
    User.any_instance.expects(:clear_issue_assignments).with(scope: @repo.issues)
    User.any_instance.expects(:unstar).with(@repo)
    Repository.any_instance.expects(:remove_fork_for).with(@outside_collaborator, @admin)
    Notifications::Subscriptions.expects(:async_delete_user_subscriptions_for_lists).with do |arg|
      arg[:user_id] == @outside_collaborator.id &&
        arg[:lists].length == 1 &&
        arg[:lists][0].type == "Repository" &&
        arg[:lists][0].id == @repo.id
    end

    Repository.any_instance.expects(:remove_from_forks).never

    @repo.disassociate_member(@outside_collaborator, @admin)
    RemoveUserFromRepoCleanupJob.perform_now(actor_id: @admin.id, member_id: @outside_collaborator.id, repo_id: @repo.id)
  end

  test "does the correct actions for an internal repo" do
    internal_repo = create(:internal_repository, owner: @org)
    internal_repo.add_member(@outside_collaborator, action: :write)

    Repository.any_instance.expects(:cancel_all_invitations_from_user).with(@outside_collaborator, @admin)
    User.any_instance.expects(:clear_issue_assignments).with(scope: internal_repo.issues)
    User.any_instance.expects(:unstar).with(internal_repo)
    Repository.any_instance.expects(:remove_fork_for).with(@outside_collaborator, @admin)
    Repository.any_instance.expects(:remove_from_forks).once.with(@outside_collaborator, @admin)
    Notifications::Subscriptions.expects(:async_delete_user_subscriptions_for_lists).with do |arg|
      arg[:user_id] == @outside_collaborator.id &&
        arg[:lists].length == 1 &&
        arg[:lists][0].type == "Repository" &&
        arg[:lists][0].id == internal_repo.id
    end

    internal_repo.disassociate_member(@outside_collaborator, @admin)
    RemoveUserFromRepoCleanupJob.perform_now(actor_id: @admin.id, member_id: @outside_collaborator.id, repo_id: internal_repo.id)
  end

  test "does all the removal steps for a public repo that's been marked inactive" do
    public_repo = create(:public_repository)
    public_repo.add_member(@outside_collaborator, action: :write)

    Repository.any_instance.expects(:cancel_all_invitations_from_user).with(@outside_collaborator, @admin)
    User.any_instance.expects(:clear_issue_assignments).with(scope: public_repo.issues)
    User.any_instance.expects(:unstar).with(public_repo)
    Repository.any_instance.expects(:remove_fork_for).with(@outside_collaborator, @admin)

    Repository.any_instance.expects(:remove_from_forks).never
    Notifications::Subscriptions.expects(:async_delete_user_subscriptions_for_lists).never

    public_repo.disassociate_member(@outside_collaborator, @admin)
    public_repo.remove(public_repo.owner)
    RemoveUserFromRepoCleanupJob.perform_now(actor_id: @admin.id, member_id: @outside_collaborator.id, repo_id: public_repo.id)
  end

  test "enqueues DenyForkCollabStateForUserPullRequestsJob if a user's collab grant is revoked, but they still have access" do
    @repo.add_member(@member, action: :maintain)

    Repository.any_instance.expects(:cancel_all_invitations_from_user).never
    User.any_instance.expects(:clear_issue_assignments).never
    User.any_instance.expects(:unstar).never
    Repository.any_instance.expects(:remove_fork_for).never

    @repo.disassociate_member(@member, @admin)
    RemoveUserFromRepoCleanupJob.perform_now(actor_id: @admin.id, member_id: @member.id, repo_id: @repo.id)

    assert_enqueued_jobs 1, only: DenyForkCollabStateForUserPullRequestsJob, queue: :deny_fork_collab_state
    assert_enqueued_with job: DenyForkCollabStateForUserPullRequestsJob, args: [user_id: @member.id, resource_id: @repo.id, resource_class: @repo.class.name]
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RemoveUserFromRepoCleanupJob, args: [actor_id: @admin.id, member_id: @member.id, repo_id: @repo.id]
  end

  context "#remove_user_from_business", skip_enterprise: true do
    test "handles scenario when repo is not owned by business" do
      repo = create(:repository, owner: create(:organization))
      repo.add_member(@outside_collaborator, action: :write)

      assert_nil RemoveUserFromRepoCleanupJob.new.remove_user_from_business(repo, @outside_collaborator)
    end

    test "calls business remove users from business when repo is owned by a business" do
      if @business.feature_enabled?(:remove_unaffiliated_users_from_business)
        Business.any_instance.expects(:update_license_usage).once
      else
        Business.any_instance.expects(:remove_user_from_business).with(@outside_collaborator, force: false).once
      end

      @business.add_user_accounts([@outside_collaborator.id])
      @repo.disassociate_member(@outside_collaborator, @admin)

      RemoveUserFromRepoCleanupJob.perform_now(actor_id: @admin.id, member_id: @outside_collaborator.id, repo_id: @repo.id)
    end
  end
end
