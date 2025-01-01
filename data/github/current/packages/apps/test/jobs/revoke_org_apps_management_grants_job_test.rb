# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RevokeOrgAppsManagementGrantsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @org = create(:organization, login: "remove-member-org")
    @user = create(:user)
    @org.add_member(@user)
    @integration = create(:integration, owner: @org)
  end

  test "revokes all-apps grants" do
    grant_result = grant_all_apps_management(user: @user, org: @org)
    assert_predicate grant_result, :success?
    assert manages_all_integrations?(user: @user, owner: @org),
           "expected grant to manage all apps"

    RevokeOrgAppsManagementGrantsJob.perform_now(@org, @user)

    refute manages_all_integrations?(user: @user, owner: @org),
           "expected to not have grants on all apps"
  end

  test "revokes single apps grants" do
    other_integration = create(:integration, owner: @org)

    grant_result = grant_app_management(user: @user, app: @integration)
    assert_predicate grant_result, :success?
    assert manages_integration?(user: @user, integration: @integration),
           "expected user to have grant on app"
    refute manages_integration?(user: @user, integration: other_integration)

    RevokeOrgAppsManagementGrantsJob.perform_now(@org, @user)

    refute manages_integration?(user: @user, integration: @integration),
           "expected user to not have grant on app"
  end

  test "raises a retriable RevocationError exception on failed all-apps revocation attempts" do
    Permissions::Granter.expects(:revoke).with(
      actor_id: @user.id,
      action: :manage_all_apps,
      subject_id: @org.id,
      entry_point: :manage_integrations_revoke_job
    ).returns(
      Permissions::GrantResult.failure!(reason: "boom"),
    )

    RevokeOrgAppsManagementGrantsJob.perform_now(@org, @user)
    # Assert the retry job is enqueued
    assert_enqueued_jobs 1, only: RevokeOrgAppsManagementGrantsJob
  end

  test "raises a retriable RevocationError exception on failed single apps revocation attempts" do
    job = RevokeOrgAppsManagementGrantsJob.new(@org, @user)
    job.expects(:revoke_single_app_grant).
      with(@integration).
      returns(Permissions::GrantResult.failure!(reason: "boom"))

    job.perform_now
    # Assert the retry job is enqueued
    assert_enqueued_jobs 1, only: RevokeOrgAppsManagementGrantsJob
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RevokeOrgAppsManagementGrantsJob, args: [@org, @user]
  end
end
