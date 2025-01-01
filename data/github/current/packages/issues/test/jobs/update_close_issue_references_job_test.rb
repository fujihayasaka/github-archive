# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdateCloseIssueReferencesJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @repo = create(:repository)
  end

  test "retries on recoverable_exceptions" do
    assert_retry_on_recoverable_exceptions job: UpdateCloseIssueReferencesJob, args: ["some_id"]
  end

  test "does not raise when issue_id is not found" do
    assert_nothing_raised do
      UpdateCloseIssueReferencesJob.perform_now("some_id")
    end
  end

  test "deletes an outdated CloseIssueReference when PR body no longer closes an issue" do
    issue = create(:issue, repository: @repo)
    pull_issue = create(:issue, body: "This fixes ##{issue.number}.", repository: @repo)

    GitHub.context.push(actor_id: pull_issue.user.id)

    only = [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]
    pull = perform_enqueued_jobs(only: only) do
      create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo)
    end
    refute_empty pull.close_issue_references

    pull_issue.body = "Some random text"
    pull_issue.save!
    assert_difference("pull.reload.close_issue_references.count", -1) do
      UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)
    end

    assert_empty pull.close_issue_references
  end

  test "deletes an existing CloseIssueReference when PR author is now spammy" do
    issue = create(:issue, repository: @repo)
    pull_issue = create(:issue, body: "This fixes ##{issue.number}.", repository: @repo)
    pull = create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo)

    GitHub.context.push(actor_id: pull_issue.user.id)

    assert_difference("CloseIssueReference.xref.count") do
      UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)
    end
    refute_empty pull.close_issue_references

    # mark pr author as spammy
    pull.update_column(:user_hidden, true)
    pull_issue.update_column(:user_hidden, true)
    assert pull.spammy?
    assert pull_issue.spammy?

    pull_issue.body = "Some random text"
    pull.save!
    assert_difference("CloseIssueReference.xref.count", -1) do
      UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)
    end
    assert_empty pull.reload.close_issue_references
  end

  test "creates a close issue reference via a linked branch, then deletes the branch ref" do
    user = create :user
    @repo.add_member user

    issue = create(:issue, repository: @repo)
    pull_issue = create(:issue, body: "This fixes ##{issue.number}.", repository: @repo, user: user)
    pull = create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo, user: user)
    create(:branch_issue_reference, issue: issue, branch_name: "topic", creator: user)

    GitHub.context.push(actor_id: pull_issue.user.id)
    UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)

    assert_equal 1, @repo.pull_requests.count
    assert CloseIssueReference.closes(issue).by_user(user).exists?
    refute BranchIssueReference.by_repo_and_branch(@repo, "topic")
  end

  test "creates a close issue reference via a linked branch, then deletes the branch ref, using the branch ref type prefix" do
    user = create :user
    @repo.add_member user

    issue = create(:issue, repository: @repo)
    pull_issue = create(:issue, body: "This fixes ##{issue.number}.", repository: @repo, user: user)
    pull = create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo, user: user, head_ref: "newbranch")
    create(:branch_issue_reference, issue: issue, branch_name: "refs/heads/newbranch", creator: user)

    GitHub.context.push(actor_id: pull_issue.user.id)
    UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)

    CloseIssueReference.closes(issue).by_user(user)

    assert_equal 1, @repo.pull_requests.count
    assert CloseIssueReference.closes(issue).by_user(user).exists?
    refute BranchIssueReference.by_repo_and_branch(@repo, "newbranch")
  end


  test "does not create a close issue reference if no issue" do
    user = create :user
    @repo.add_member user

    pull_issue = create(:issue, body: "This fixes some bug", repository: @repo, user: user)
    pull = create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo, user: user)

    GitHub.context.push(actor_id: pull_issue.user.id)
    UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)

    assert_equal 1, @repo.pull_requests.count
    refute CloseIssueReference.where(pull_request_id: pull.id).exists?
  end


  test "creates an xref CloseIssueReference when PR body closes an issue" do
    issue = create(:issue, repository: @repo)
    pull_issue = create(:issue, body: "This fixes ##{issue.number}.", repository: @repo)
    pull = create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo)

    GitHub.context.push(actor_id: pull_issue.user.id)

    assert_difference("CloseIssueReference.xref.count") do
      UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)
    end

    ref = CloseIssueReference.last
    ref = T.must(ref)
    assert ref.xref?
    assert_equal pull, ref.pull_request
    assert_equal issue, ref.issue
    assert_equal issue.repository, ref.issue_repository
    assert_equal pull.user, ref.pull_request_author
  end

  # skipping for enterprise because we do not control who they want to be spammy
  test "does not create an xref CloseIssueReference when PR author is spammy", skip_enterprise: true do
    spammy_user = create :spammy_user
    @repo.add_member spammy_user

    issue = create(:issue, repository: @repo)
    pull_issue = create(:issue, body: "This fixes ##{issue.number}.", repository: @repo, user: spammy_user)
    pull = create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo, user: spammy_user)

    GitHub.context.push(actor_id: spammy_user.id)

    assert_no_difference("CloseIssueReference.xref.count") do
      UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)
    end

    assert_nil CloseIssueReference.last
  end

  test "does not create an xref CloseIssueReference when PR body references its own issue" do
    pull_issue = create(:issue, repository: @repo)
    pull = create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo)
    pull_issue.update(body: "This fixes ##{pull_issue.number}.")

    GitHub.context.push(actor_id: pull_issue.user.id)

    assert_no_difference("CloseIssueReference.xref.count") do
      UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)
    end
  end

  test "does not create an xref CloseIssueReference when PR body references another PR" do
    other_pull_issue = create(:issue, repository: @repo)
    other_pull = create(:pull_request, :disable_disk_access, repository: @repo, head_ref: "bloop")

    pull = create(:pull_request, :disable_disk_access, repository: @repo)
    pull.issue.update(body: "This fixes ##{other_pull_issue.number}.")

    GitHub.context.push(actor_id: pull.issue.user.id)

    assert_no_difference("CloseIssueReference.xref.count") do
      UpdateCloseIssueReferencesJob.perform_now(other_pull_issue.id)
    end
  end

  test "handles when PR body closes an additional issue" do
    issue1 = create(:issue, repository: @repo)
    issue2 = create(:issue, repository: @repo)
    pull_issue = create(:issue, body: "This fixes ##{issue1.number}.", repository: @repo)

    GitHub.context.push(actor_id: pull_issue.user.id)
    only = [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]
    pull = perform_enqueued_jobs(only: only) do
      create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo)
    end

    pull_issue.body += " And also closes ##{issue2.number}!"
    pull_issue.save!
    assert_difference("CloseIssueReference.count") do
      UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)
    end

    assert_equal 2, pull.reload.close_issue_references.count
    assert_same_elements [issue1, issue2], pull.close_issue_references.includes(:issue).map(&:issue)
    assert_equal 1, issue1.close_issue_references.count
    assert_equal 1, issue2.close_issue_references.count
  end

  test "only deletes references with an xref source" do
    issue = create(:issue, repository: @repo)
    pull_issue = create(:issue, body: "This fixes ##{issue.number}.", repository: @repo)

    GitHub.context.push(actor_id: pull_issue.user.id)

    only = [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]
    pull = perform_enqueued_jobs(only: only) do
      create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo)
    end

    refute_empty pull.close_issue_references

    another_issue = create(:issue, repository: @repo)
    manual_ref = create(:manual_close_issue_reference, issue: another_issue, pull_request: pull)

    assert_equal 2, pull.close_issue_references.count

    pull_issue.body = "Some random text"
    pull_issue.save!
    pull.reload

    assert_difference("pull.close_issue_references.xref.count", -1) do
      UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)
    end

    assert_equal 1, pull.close_issue_references.manual.count
  end

  test "re-enqueues the job if Aqueduct::Worker::JobKilled error is raised" do
    pull_issue = create(:issue, repository: @repo)
    pull = create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo)
    pull_issue.update(body: "This fixes ##{pull_issue.number}.")

    GitHub.context.push(actor_id: pull_issue.user.id)

    UpdateCloseIssueReferencesJob.any_instance.stubs(:perform).raises(Aqueduct::Worker::JobKilled)
    assert_enqueued_with(job: UpdateCloseIssueReferencesJob, args: [pull_issue.id]) do
      UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)
    end
  end

  test "re-enqueues the job if GitHub::Restraint::UnableToLock error is raised" do
    pull_issue = create(:issue, repository: @repo)
    pull = create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo)
    pull_issue.update(body: "This fixes ##{pull_issue.number}.")

    GitHub.context.push(actor_id: pull_issue.user.id)

    UpdateCloseIssueReferencesJob.any_instance.stubs(:perform).raises(GitHub::Restraint::UnableToLock)
    assert_enqueued_with(job: UpdateCloseIssueReferencesJob, args: [pull_issue.id]) do
      UpdateCloseIssueReferencesJob.perform_now(pull_issue.id)
    end
  end

  if GitHub.multi_tenant_enterprise?
    test "logs warning if the tenant context can not be resolved" do
      GitHub::CurrentTenant.remove

      logs = capture_logs do
        UpdateCloseIssueReferencesJob.perform_now("some_id")
      end

      assert logs.include?("Could not find a tenant to resolve for job")
    end

    test "resolves the tenant context using the issue repository tenant" do
      GitHub::CurrentTenant.remove

      issue = create(:issue, repository: @repo)

      GitHub.context.push(actor_id: issue.user.id)

      UpdateCloseIssueReferencesJob.perform_now(issue.id)

      assert_equal issue.repository.tenant_id, GitHub::CurrentTenant.get.id
    end
  end
end
