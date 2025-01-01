# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require File.join(Rails.root, "packages/repositories/test/jobs/remove_org_member_data_common_tests")

class RemoveOrgMemberIssueAssignmentsJobTest < GitHub::TestCase
  include RemoveOrgMemberDataCommonTests
  include JobTestHelper

  REPOS_OPTIMIZER_HINT_REGEX = Regexp.new(Regexp.escape("/*+ INDEX(repositories index_repos_on_organization_id_active_public_and_parent_id) */"))

  fixtures do
    @restorable_org_user = create :restorable_organization_user
    @org = @restorable_org_user.organization
    @org.allow_private_repository_forking(actor: @org.admin)
    @user = @restorable_org_user.user
    @private_repo = create(:private_repository, :minimal, owner: @org)
    @private_repo2 = create(:private_repository, :minimal, owner: @org)
    @private_repo3 = create(:private_repository, :minimal, owner: @org)
    @public_repo = create(:repository, :minimal, owner: @org)
  end

  test "handles dirty exit" do
    assert_retry_on_dirty_exit job: RemoveOrgMemberIssueAssignmentsJob, args: [@org, @user]
  end

  test "enqueues job for restoring an organization user" do
    assert_enqueued_with job: RemoveOrgMemberIssueAssignmentsJob, queue: "remove_org_member_issue_assignments" do
      RemoveOrgMemberIssueAssignmentsJob.perform_later(@org, @user)
    end
  end

  test "#perform should remove issue assignments" do
    @org.add_member(@user)
    private_issue = create(:issue, repository: @private_repo, assignee: @user)
    private_issue.reload
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert_includes private_issue.assignees, @user
    RemoveOrgMemberIssueAssignmentsJob.perform_now(@org, @user)
    refute_includes private_issue.assignees, @user
  end

  test "#perform should not remove public issue assignments" do
    @org.add_member(@user)
    private_issue = create(:issue, repository: @private_repo, assignee: @user)
    private_issue.reload
    private_issue2 = create(:issue, repository: @private_repo2, assignee: @user)
    private_issue2.reload
    public_issue = create(:issue, repository: @public_repo, assignee: @user)
    public_issue.reload
    @org.remove_member_without_callbacks_and_notifications(@user)

    RemoveOrgMemberIssueAssignmentsJob.perform_now(@org, @user)

    assert_includes public_issue.assignees, @user
    refute_includes private_issue.assignees, @user
    refute_includes private_issue2.assignees, @user
  end

  test "#perform does not remove issue assignments if repository is pullable by user" do
    @org.add_member(@user)
    private_issue = create(:issue, repository: @private_repo, assignee: @user)
    private_issue.reload
    private_issue2 = create(:issue, repository: @private_repo2, assignee: @user)
    private_issue2.reload
    public_issue = create(:issue, repository: @public_repo, assignee: @user)
    public_issue.reload
    @private_repo.add_member(@user)
    @org.remove_member_without_callbacks_and_notifications(@user)

    RemoveOrgMemberIssueAssignmentsJob.perform_now(@org, @user)

    assert_includes public_issue.assignees, @user
    assert_includes private_issue.assignees, @user
    refute_includes private_issue2.assignees, @user
  end

  test "#perform does not remove issue assignments in private archived repositories" do
    @org.add_member(@user)
    private_issue = create(:issue, repository: @private_repo, assignee: @user)
    private_issue.reload
    archived_repo = create(:private_repository, :minimal, owner: @org)
    private_archived_issue = create(:issue, repository: archived_repo, assignee: @user)
    private_archived_issue.reload
    @org.remove_member_without_callbacks_and_notifications(@user)
    archived_repo.set_archived

    assert_includes private_issue.assignees, @user
    assert_includes private_archived_issue.assignees, @user

    RemoveOrgMemberIssueAssignmentsJob.perform_now(@org, @user)

    refute_includes private_issue.assignees, @user
    assert_includes private_archived_issue.assignees, @user
  end

  test "#perform should add multiple issue assignment restorables" do
    @org.add_member(@user)
    private_issue = create(:issue, repository: @private_repo, assignee: @user)
    private_issue2 = create(:issue, repository: @private_repo2, assignee: @user)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert_difference "Restorable::IssueAssignment.count", 2 do
      RemoveOrgMemberIssueAssignmentsJob.perform_now(@org, @user)
    end
  end

  test "#perform should not create issue assignment restorables for public repos" do
    @org.add_member(@user)
    private_issue = create(:issue, repository: @private_repo, assignee: @user)
    private_issue2 = create(:issue, repository: @private_repo2, assignee: @user)
    public_issue = create(:issue, repository: @public_repo, assignee: @user)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert_difference "Restorable::IssueAssignment.count", 2 do
      RemoveOrgMemberIssueAssignmentsJob.perform_now(@org, @user)
    end
  end

  test "#perform does not create restorables if no Restorable::OrganizationUser record is found" do
    user = create(:user)
    @org.add_member(user)
    issue = create(:issue, repository: @private_repo, assignee: user)
    issue2 = create(:issue, repository: @private_repo2, assignee: user)
    @org.remove_member_without_callbacks_and_notifications(user)

    assert_difference "Restorable::IssueAssignment.count", 0 do
      RemoveOrgMemberIssueAssignmentsJob.perform_now(@org, @user)
    end
  end

  test "#perform should mark issue assignment restorable as complete" do
    @org.add_member(@user)
    private_issue = create(:issue, repository: @private_repo, assignee: @user)
    private_issue2 = create(:issue, repository: @private_repo2, assignee: @user)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert_difference "Restorable::IssueAssignment.count", 2 do
      RemoveOrgMemberIssueAssignmentsJob.perform_now(@org, @user)
    end

    assert @restorable_org_user.restorable.saved?([:restorable_issue_assignments]),
      "expected restorable_issue_assignments to be saved"
  end

  test "retries the job if a throttling error occurs" do
    @org.add_member(@user)
    private_issue = create(:issue, repository: @private_repo, assignee: @user)
    private_issue2 = create(:issue, repository: @private_repo2, assignee: @user)
    @org.remove_member_without_callbacks_and_notifications(@user)
    verify_throttling(RemoveOrgMemberIssueAssignmentsJob, @org, @user)
  end

  context "handles exceptions and error cases, and signals Failbot when one occurs" do
    test "finishes successfully and does not call Failbot if each repo has a valid RepositoryNetwork" do
      verify_no_failbot_calls_by_default(RemoveOrgMemberIssueAssignmentsJob, @org, @user)
    end

    test "calls via #pullable_by_user_or_no_plan_owner? (to handle exceptions from a bad RepositoryNetwork on any repos) and finishes running without raising any uncaught exceptions" do
      disable_feature_flag(:remove_org_member_issue_assignments_job_repo_optimization)
      perform_bad_network_test(RemoveOrgMemberIssueAssignmentsJob, @org, @user)
    end
  end

  context "batching" do
    test "removes all user assignments if there are more issues than the issue batch limit" do
      @org.add_member(@user)

      private_issue  = create(:issue, repository: @private_repo, assignee: @user)
      private_issue2 = create(:issue, repository: @private_repo, assignee: @user)
      private_issue3 = create(:issue, repository: @private_repo, assignee: @user)

      @org.remove_member_without_callbacks_and_notifications(@user)

      private_issues = Issue
        .where(repository_id: @private_repo.id)
        .assigned_to(@user)
        .all

      assert_equal 3, private_issues.size

      RemoveOrgMemberIssueAssignmentsJob.stub_const(:ISSUE_BATCH_SIZE, 2) do
        assert_performed_jobs GitHub.flipper[:remove_org_member_issue_assignments_job_repo_optimization].enabled? ? 1 : 2, only: RemoveOrgMemberIssueAssignmentsJob do
          RemoveOrgMemberIssueAssignmentsJob.perform_later(@org, @user)
        end
      end

      user_issues = Issue
        .where(repository_id: @private_repo.id)
        .assigned_to(@user)
        .all

      assert_empty user_issues
    end

    test "removes all user assignments if there are more repos than the repo batch limit" do
      @org.add_member(@user)

      private_issue  = create(:issue, repository: @private_repo, assignee: @user)
      private_issue2 = create(:issue, repository: @private_repo2, assignee: @user)
      private_issue3 = create(:issue, repository: @private_repo3, assignee: @user)

      @org.remove_member_without_callbacks_and_notifications(@user)

      private_issues = Issue
        .where(repository_id: [@private_repo.id, @private_repo2.id, @private_repo3.id])
        .assigned_to(@user)
        .all

      assert_equal 3, private_issues.size

      RemoveOrgMemberIssueAssignmentsJob.stub_const(:REPO_BATCH_SIZE, 2) do
        assert_performed_jobs GitHub.flipper[:remove_org_member_issue_assignments_job_repo_optimization].enabled? ? 1 : 2, only: RemoveOrgMemberIssueAssignmentsJob do
          RemoveOrgMemberIssueAssignmentsJob.perform_later(@org, @user)
        end
      end

      user_issues = Issue
        .where(repository_id: [@private_repo.id, @private_repo2.id, @private_repo3.id])
        .assigned_to(@user)
        .all

      assert_empty user_issues
    end

    test "removes all user assignments when found repo and issue sizes match batch limits" do
      @org.add_member(@user)

      private_issue  = create(:issue, repository: @private_repo, assignee: @user)
      private_issue2 = create(:issue, repository: @private_repo, assignee: @user)
      private_issue3 = create(:issue, repository: @private_repo2, assignee: @user)
      private_issue4 = create(:issue, repository: @private_repo2, assignee: @user)
      private_issue5 = create(:issue, repository: @private_repo3, assignee: @user)
      private_issue6 = create(:issue, repository: @private_repo3, assignee: @user)

      @org.remove_member_without_callbacks_and_notifications(@user)

      private_issues = Issue
        .where(repository_id: [@private_repo.id, @private_repo2.id, @private_repo3.id])
        .assigned_to(@user)
        .all

      assert_equal 6, private_issues.size

      RemoveOrgMemberIssueAssignmentsJob.stub_const(:REPO_BATCH_SIZE, 2) do
        RemoveOrgMemberIssueAssignmentsJob.stub_const(:ISSUE_BATCH_SIZE, 2) do
          # why 5:
          #   1: [repo1, repo2]: [issue1, issue2] ... maybe more issues, enqueue next job
          #   2: [repo1, repo2]: [issue3, issue4] ... maybe more issues, enqueue next job
          #   3: [repo1, repo2]: []               ... no more issues, enqueue next job for next repos
          #   4: [repo3]       : [issue5, issue6] ... maybe more issues, enqueue next job
          #   5: [repo3]       : []               ... no more issues, no more repos, STOP
          assert_performed_jobs GitHub.flipper[:remove_org_member_issue_assignments_job_repo_optimization].enabled? ? 1 : 5, only: RemoveOrgMemberIssueAssignmentsJob do
            RemoveOrgMemberIssueAssignmentsJob.perform_later(@org, @user)
          end
        end
      end

      user_issues = Issue
        .where(repository_id: [@private_repo.id, @private_repo2.id, @private_repo3.id])
        .assigned_to(@user)
        .all

      assert_empty user_issues
    end
  end
end
