# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require File.join(Rails.root, "packages/repositories/test/jobs/remove_org_member_data_common_tests")

class BulkBulkRemoveOrgMemberIssueAssignmentsJobTest < GitHub::TestCase
  include RemoveOrgMemberDataCommonTests
  include JobTestHelper

  REPOS_OPTIMIZER_HINT_REGEX = Regexp.new(Regexp.escape("/*+ INDEX(repositories index_repos_on_organization_id_active_public_and_parent_id) */"))

  fixtures do
    @owner = create :user
    @org = create(:organization, admin: @owner)
    @org.allow_private_repository_forking(actor: @owner)
    @user = create :user
    @org.add_member(@user)

    @private_repo = create(:private_repository, :minimal, owner: @org)
    @private_repo2 = create(:private_repository, :minimal, owner: @org)
    @private_repo3 = create(:private_repository, :minimal, owner: @org)
    @public_repo = create(:repository, :minimal, owner: @org)
  end

  test "enqueues job for restoring an organization user" do
    assert_enqueued_with job: BulkRemoveOrgMemberIssueAssignmentsJob, queue: "bulk_remove_org_member_issue_assignments" do
      BulkRemoveOrgMemberIssueAssignmentsJob.perform_later(organization_ids: [@org.id], user_id: @user.id)
    end
  end

  context "#perform" do
    test "removes issue assignments" do
      private_issue = create(:issue, repository: @private_repo, assignee: @user)
      private_issue.reload
      @org.remove_member_without_callbacks_and_notifications(@user)

      assert_includes private_issue.assignees, @user
      BulkRemoveOrgMemberIssueAssignmentsJob.perform_now(organization_ids: [@org.id], user_id: @user.id)
      refute_includes private_issue.assignees, @user
    end

    test "does not remove public issue assignments" do
      private_issue = create(:issue, repository: @private_repo, assignee: @user)
      private_issue.reload
      private_issue2 = create(:issue, repository: @private_repo2, assignee: @user)
      private_issue2.reload
      public_issue = create(:issue, repository: @public_repo, assignee: @user)
      public_issue.reload
      @org.remove_member_without_callbacks_and_notifications(@user)

      BulkRemoveOrgMemberIssueAssignmentsJob.perform_now(organization_ids: [@org.id], user_id: @user.id)

      assert_includes public_issue.assignees, @user
      refute_includes private_issue.assignees, @user
      refute_includes private_issue2.assignees, @user
    end

    test "does not remove issue assignments if repository is pullable by user" do
      private_issue = create(:issue, repository: @private_repo, assignee: @user)
      private_issue.reload
      private_issue2 = create(:issue, repository: @private_repo2, assignee: @user)
      private_issue2.reload
      public_issue = create(:issue, repository: @public_repo, assignee: @user)
      public_issue.reload
      @private_repo.add_member(@user)
      @org.remove_member_without_callbacks_and_notifications(@user)

      BulkRemoveOrgMemberIssueAssignmentsJob.perform_now(organization_ids: [@org.id], user_id: @user.id)

      assert_includes public_issue.assignees, @user
      assert_includes private_issue.assignees, @user
      refute_includes private_issue2.assignees, @user
    end

    test "does not remove issue assignments in private archived repositories" do
      private_issue = create(:issue, repository: @private_repo, assignee: @user)
      private_issue.reload
      archived_repo = create(:private_repository, :minimal, owner: @org)
      private_archived_issue = create(:issue, repository: archived_repo, assignee: @user)
      private_archived_issue.reload
      @org.remove_member_without_callbacks_and_notifications(@user)
      archived_repo.set_archived

      assert_includes private_issue.assignees, @user
      assert_includes private_archived_issue.assignees, @user

      BulkRemoveOrgMemberIssueAssignmentsJob.perform_now(organization_ids: [@org.id], user_id: @user.id)

      refute_includes private_issue.assignees, @user
      assert_includes private_archived_issue.assignees, @user
    end
  end
end
