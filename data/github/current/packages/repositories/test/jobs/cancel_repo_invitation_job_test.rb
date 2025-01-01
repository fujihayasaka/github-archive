# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CancelRepoInvitationJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @owner = create(:user)
    @repo = create(:private_repository, owner: @owner)
    @invitation = create(:repository_invitation, repository: @repo, inviter: @owner)
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: CancelRepoInvitationJob, args: [actor: @owner, invitation: @invitation]
  end

  test "cancels an invitation" do
    CancelRepoInvitationJob.perform_now(actor: @owner, invitation: @invitation)

    assert_empty RepositoryInvitation.where(id: @invitation.id)
  end

  test "raises an error if the inviter is not a repo admin" do
    repo_member = create(:user)
    @repo.add_member(repo_member)

    assert_raises RuntimeError do
      CancelRepoInvitationJob.perform_now(actor: repo_member, invitation: @invitation)
    end

    refute_empty RepositoryInvitation.where(id: @invitation.id)
  end

  test "does not raise an error if the inviter is not a repo admin but permit_non_repo_admins is true" do
    repo_member = create(:user)
    @repo.add_member(repo_member)

    CancelRepoInvitationJob.perform_now \
      actor: repo_member,
      invitation: @invitation,
      permit_non_repo_admins: true

    assert_empty RepositoryInvitation.where(id: @invitation.id)
  end

  test "raises an error if the inviter has been removed from the repo" do
    repo_admin = create(:user)
    @repo.add_member(repo_admin, action: :admin)

    @repo.remove_member(repo_admin)

    # Simulating a job that has been enqueued by the repo_admin, but has presently been
    # removed from the repository
    assert_raises RuntimeError do
      CancelRepoInvitationJob.perform_now(actor: repo_admin, invitation: @invitation)
    end

    refute_empty RepositoryInvitation.where(id: @invitation.id)
  end
end
