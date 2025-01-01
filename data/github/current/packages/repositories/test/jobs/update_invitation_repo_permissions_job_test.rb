# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdateInvitationRepoPermissionsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @inviter = create(:user)
    @repo = create(:org_owned_repository)
    @repo.organization.add_member(@inviter, action: :admin)

    @invitation = create(
      :repository_invitation,
      inviter: @inviter,
      repository: @repo,
      permissions: :write,
    )
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: UpdateInvitationRepoPermissionsJob, args: [@invitation, { action: :admin, setter: @inviter }]
  end

  test "can upgrade an invitation permission for the repo" do
    UpdateInvitationRepoPermissionsJob.perform_now(@invitation, action: :maintain, setter: @inviter)
    assert_equal @invitation.reload.permissions, "maintain"
  end

  test "can downgrade an invitation permission for the repo" do
    UpdateInvitationRepoPermissionsJob.perform_now(@invitation, action: :triage, setter: @inviter)
    assert_equal @invitation.reload.permissions, "triage"
  end

  test "will not update an invitation that the setter can't modify" do
    random_user = create(:user)

    assert_raises RepositoryInvitation::InsufficientAbilities do
      UpdateInvitationRepoPermissionsJob.perform_now(@invitation, action: :admin, setter: random_user)
    end

    assert_equal @invitation.reload.permissions, "write"
  end

  test "raises error for empty setter" do
    assert_raises ArgumentError do
      UpdateInvitationRepoPermissionsJob.perform_now(@invitation, action: :triage, setter: nil)
    end

    assert_equal @invitation.reload.permissions, "write"
  end

  test "raises error for invalid action" do
    assert_raises ArgumentError do
      UpdateInvitationRepoPermissionsJob.perform_now(@invitation, action: :blah, setter: @inviter)
    end

    assert_equal @invitation.reload.permissions, "write"
  end

  test "raises when action is invalid and setter has insufficient permissions" do
    random_user = create(:user)

    assert_raises do
      UpdateInvitationRepoPermissionsJob.perform_now(@invitation, action: :blah, setter: random_user)
    end

    assert_equal @invitation.reload.permissions, "write"
  end
end
