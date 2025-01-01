# typed: true
# frozen_string_literal: true

require "test_helper"

class DestroyBranchIssueReferencesJobTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @deleted_branch_name = "deleted-branch"
    @user = create(:user)
  end

  setup do
    example_repo :simple, @repo
  end

  test "will still remove references if the repo has been deleted" do
    issue1 = create(:issue, repository: @repo)
    ref1 = create(:branch_issue_reference, issue: issue1, branch_name: @deleted_branch_name)

    @repo.destroy
    assert_difference "BranchIssueReference.count", -1 do
      DestroyBranchIssueReferencesJob.perform_now(@repo.id, @deleted_branch_name)
    end
  end

  test "deletes every ref to the given nonexistant branch for the repo regardless of the issue" do
    issue1 = create(:issue, repository: @repo)
    issue2 = create(:issue, repository: @repo)

    ref1 = create(:branch_issue_reference, issue: issue1, branch_name: @deleted_branch_name)
    ref2 = create(:branch_issue_reference, issue: issue2, branch_name: @deleted_branch_name)

    assert_difference "BranchIssueReference.count", -2 do
      DestroyBranchIssueReferencesJob.perform_now(@repo.id, @deleted_branch_name)
    end
  end

  test "does not delete a ref if the branch doesn't match" do
    issue1 = create(:issue, repository: @repo)
    branch = "some-branch"

    ref1 = create(:branch_issue_reference, issue: issue1, branch_name: "some-other-branch")

    assert_no_difference "BranchIssueReference.count" do
      DestroyBranchIssueReferencesJob.perform_now(@repo.id, @deleted_branch_name)
    end
  end

  test "does not delete the reference when the branch still exists" do
    master_oid = @repo.heads["master"].target_oid
    branch = "some-branch"
    topic = @repo.heads.create(branch, master_oid, @user)

    issue1 = create(:issue, repository: @repo)

    ref1 = create(:branch_issue_reference, issue: issue1, branch_name: branch)

    assert_no_difference "BranchIssueReference.count" do
      DestroyBranchIssueReferencesJob.perform_now(@repo.id, branch)
    end
  end

  test "re-enqueues the job if Aqueduct::Worker::JobKilled error is raised" do
    DestroyBranchIssueReferencesJob.any_instance. stubs(:perform).raises(Aqueduct::Worker::JobKilled)
    assert_enqueued_with(job: DestroyBranchIssueReferencesJob, args: [@repo.id, "test"]) do
      DestroyBranchIssueReferencesJob.perform_now(@repo.id, "test")
    end
  end
end
