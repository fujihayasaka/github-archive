# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/job_test_helper"

class PullRequests::Orchestrations::ResolveConflictTest < GitHub::TestCase
  include DogstatsTestHelpers
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @owner = create(:user, login: "alice", plan: "large")
    @repo = create(:repository, owner: @owner, name: "repo", from_example: :conflicts)


    @pull_request = create(:pull_request,
      repository: @repo,
      user: @owner,
      base_repository: @repo,
      head_repository: @repo,
      base_ref: "conflicts-base",
      head_ref: "conflicts",
      title: "blah",
      body: "blah"
    )
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "generates the merge commit synchronously but does not persist it" do
    head_sha_before = @pull_request.head_sha

    orchestration = PullRequests::Orchestrations::ResolveConflicts.create(
      repository: @pull_request.repository,
      pull_request: @pull_request,
      user: @owner,
      expected_head_oid: @pull_request.head_sha,
      base_oid: @pull_request.base_sha,
      resolve_conflicts: { "file2" => "meep\r\nmoop\r\n", CGI.escape("R\351sum\351") => "resolved!!!!!\n" },
    )
    with_enqueued_pr_sync_jobs do
      orchestration.execute!
    end

    assert_predicate orchestration.reload, :running?
    expected_step = "job_start"
    assert_equal expected_step, orchestration.step_name
    assert_equal @pull_request.reload.head_sha, head_sha_before
  end

  test "persists the resolution in background job" do
    head_sha_before = @pull_request.head_sha

    orchestration = PullRequests::Orchestrations::ResolveConflicts.create(
      repository: @pull_request.repository,
      pull_request: @pull_request,
      user: @owner,
      expected_head_oid: @pull_request.head_sha,
      base_oid: @pull_request.base_sha,
      resolve_conflicts: { "file2" => "meep\r\nmoop\r\n", CGI.escape("R\351sum\351") => "resolved!!!!!\n" }
    )

    with_enqueued_pr_sync_jobs(additional_jobs: [PullRequestOrchestrationJob]) do
      orchestration.execute!

      assert_predicate orchestration.reload, :succeeded?
      refute_equal @pull_request.reload.head_sha, head_sha_before
    end
  end

  test "ensures use has write permissions to the head ref" do
    head_sha_before = @pull_request.head_sha
    rando = create(:user)

    orchestration = PullRequests::Orchestrations::ResolveConflicts.create(
      repository: @pull_request.repository,
      pull_request: @pull_request,
      user: rando,
      expected_head_oid: @pull_request.head_sha,
      base_oid: @pull_request.base_sha,
      resolve_conflicts: { "file2" => "meep\r\nmoop\r\n", CGI.escape("R\351sum\351") => "resolved!!!!!\n" }
    )
    with_enqueued_pr_sync_jobs(additional_jobs: [PullRequestOrchestrationJob]) do
      orchestration.execute!

      assert_predicate orchestration.reload, :failed?
      assert_equal orchestration.error_message, "user doesn't have permission to update head repository"
      assert_equal @pull_request.reload.head_sha, head_sha_before
    end
  end
end
