# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::Orchestrations::MergeTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :simple)
    @pull = create(:pull_request, :with_mergeable_head, user: @user, repository: @repo)
    example_repo_snapshot
  end

  setup do
    example_repo_restore

    Spokesd.enable_spokesd
  end

  test "merges a pull request" do
    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    perform_enqueued_jobs(only: PullRequestOrchestrationJob) do
      orchestration.execute!
    end

    assert_predicate orchestration.reload, :succeeded?
    assert_predicate @pull.reload, :merged?
  end

  test "lets you pass a commit message" do
    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
      commit_title: "asdf",
      commit_body: "asdfghjkl"
    )

    perform_enqueued_jobs(only: PullRequestOrchestrationJob) do
      orchestration.execute!
    end

    assert_predicate orchestration.reload, :succeeded?
    assert_predicate @pull.reload, :merged?

    merge_commit = @pull.repository.commits.find(@pull.merge_commit_sha)
    assert_match /asdfghjkl/, merge_commit.message
  end

  test "catches git errors" do
    PullRequest::Merge.any_instance.expects(:prepare_and_validate).raises(Git::Ref::ComparisonMismatch)

    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    orchestration.execute!

    assert_predicate orchestration, :skipped?
    assert_equal "Base branch was modified. Review and try the merge again.", orchestration.error_message
  end

  test "catches non-git errors" do
    @pull.convert_to_draft(user: @user)

    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    orchestration.execute!

    assert_predicate orchestration, :skipped?
    assert_equal "Pull Request is still a draft", orchestration.error_message
  end

  test "deletes head branch when settings permit" do
    @pull.head_repository.update_merge_settings(@user, delete_branch_allowed: true)

    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    perform_enqueued_jobs(only: PullRequestOrchestrationJob) do
      orchestration.execute!
    end

    assert_predicate orchestration.reload, :succeeded?
    refute_predicate @pull, :head_ref_exist?
  end

  test "it does not halt when deleting branches violates branch rules" do
    @pull.head_repository.update_merge_settings(@user, delete_branch_allowed: true)

    Git::Ref.any_instance.expects(:delete).raises(
      Git::Ref::ProtectedBranchUpdateError.new(nil, nil, "branch is protected from deleting")
    )

    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    perform_enqueued_jobs(only: PullRequestOrchestrationJob) do
      orchestration.execute!
    end

    assert_predicate orchestration.reload, :succeeded?
    assert_predicate @pull, :head_ref_exist?
  end

  test "does not delete head branch when settings do not permit" do
    @pull.head_repository.update_merge_settings(@user, delete_branch_allowed: false)

    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    perform_enqueued_jobs(only: PullRequestOrchestrationJob) do
      orchestration.execute!
    end

    assert_predicate orchestration.reload, :succeeded?
    assert_predicate @pull, :head_ref_exist?
  end

  test "destroys last seen revisions" do
    last_seen_pull_request_revision = LastSeenPullRequestRevision.create(pull_request: @pull, user_id: @user.id, last_revision: "abc")

    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    assert_equal [last_seen_pull_request_revision], @pull.last_seen_pull_request_revisions

    perform_enqueued_jobs(only: PullRequestOrchestrationJob) do
      orchestration.execute!
    end

    assert_predicate orchestration.reload, :succeeded?
    assert_equal [], @pull.last_seen_pull_request_revisions
  end

  test "destroys conflict metadata" do
    pull_request_conflict = PullRequestConflict.create(pull_request: @pull, base_sha: SecureRandom.hex(20), head_sha: SecureRandom.hex(20), conflict_type: :merge_conflict)

    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    assert_equal pull_request_conflict, @pull.conflict

    perform_enqueued_jobs(only: PullRequestOrchestrationJob) do
      orchestration.execute!
    end

    assert_predicate orchestration.reload, :succeeded?
    assert_nil @pull.reload.conflict
  end

  test "allows squash merge with checks" do
    with_enqueued_pr_sync_jobs do
      @pull.base_repository.heads.find(@pull.head_ref).append_commit({
        message: "blah", committer: @user
      }, @user) do |files|
        files.add("SOME-RANDOM-FILE.md", "foobar")
      end
    end
    @pull.reload


    @repo.protect_branch(@pull.base_ref, creator: @user, required_status_checks: { contexts: %w[ci/janky], include_admins: true }, entry_point: :test_case)

    check_suite  = create(:check_suite, repository: @repo, head_sha: @pull.head_sha, name: "CI build", event: "push")
    _check_run   = create(:check_run, name: "ci/janky", check_suite: check_suite, status: :completed, completed_at: 1.day.ago, conclusion: :success)

    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :squash,
    )

    perform_enqueued_jobs(only: PullRequestOrchestrationJob) do
      orchestration.execute!
    end

    assert_predicate orchestration.reload, :succeeded?
    assert_predicate @pull.reload, :merged?
  end

  test "does not allow duplicate orchestrations" do
    PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    orchestration = PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )
    refute orchestration.persisted?
    assert_equal "Merge already in progress", orchestration.errors.full_messages.first
  end

  test "marks the orchestration as abandoned if updated 90 seconds ago and before job_start" do
    enable_feature_flag(:mark_dangling_orchestrations_as_abandoned)

    orchestration = Timecop.freeze(91.seconds.ago) do
      PullRequests::Orchestrations::Merge.create(
        repository: @pull.repository,
        pull_request: @pull,
        actor: @user,
        method: :merge
      )
    end

    PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    orchestration.reload

    assert_equal "abandoned", orchestration.state
  end

  test "does not update non-active orchestration as abandoned if updated more than 90 seconds ago and before job_start" do
    enable_feature_flag(:mark_dangling_orchestrations_as_abandoned)

    orchestration = Timecop.freeze(91.seconds.ago) do
      PullRequests::Orchestrations::Merge.create(
        repository: @pull.repository,
        pull_request: @pull,
        actor: @user,
        method: :merge,
      )
    end
    orchestration.update(state: :failed)

    PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    orchestration.reload

    assert_equal "failed", orchestration.state
  end

  test "logs when marking dangling orchestrations" do
    enable_feature_flag(:mark_dangling_orchestrations_as_abandoned)

    orchestration = Timecop.freeze(2.minutes.ago) do
      PullRequests::Orchestrations::Merge.create(
        repository: @pull.repository,
        pull_request: @pull,
        actor: @user,
        method: :merge
      )
    end

    GitHub.logger.stubs(:info).returns(true)
    GitHub.logger.expects(:info).with(
      "marking dangling merge orchestrations as abandoned",
      "code.namespace": "PullRequests::Orchestrations::Merge",
      "gh.repository.id": @pull.repository.id,
      "gh.pull_request.id": @pull.id,
    )

    PullRequests::Orchestrations::Merge.create(
      repository: @pull.repository,
      pull_request: @pull,
      actor: @user,
      method: :merge,
    )

    orchestration.reload
  end
end
