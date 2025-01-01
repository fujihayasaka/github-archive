# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeScanningCheckSuiteTest < GitHub::TestCase
  fixtures do
    @cs_check_suite = create(:code_scanning_check_suite)
    make_trusted_oauth_apps_owner
    @integration = create(:code_scanning_integration)
  end

  test "is deleted after check suite destruction" do
    assert_difference("CodeScanningCheckSuite.where(repository_id: #{@cs_check_suite.repository_id}).count", -1) do
      @cs_check_suite.check_suite.destroy
    end
  end

  test "is deleted after repository soft-deletion" do
    repo = @cs_check_suite.repository

    assert_difference("CodeScanningCheckSuite.where(repository_id: #{@cs_check_suite.repository_id}).count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.remove(repo.owner, synchronous: true)
      end
    end
  end

  test "for_check_run" do
    check_run = create(:check_run, check_suite: @cs_check_suite.check_suite)
    assert_equal @cs_check_suite, CodeScanningCheckSuite.for_check_run(check_run)
  end

  test "merge_commit_for without code scanning check suite" do
    repo = create(:repository, from_example: :pull_request_source)
    pull_request = create(:pull_request, :with_mergeable_head, repository: repo)
    check_suite = create(:check_suite, head_sha: pull_request.head_sha, repository: repo, github_app: @integration, status: :completed)

    assert_equal pull_request.merge_commit_sha, CodeScanningCheckSuite.merge_commit_for(pull_request:)
  end

  test "merge_commit_for with code scanning check suite" do
    repo = create(:repository, from_example: :pull_request_source)
    pull_request = create(:pull_request, :with_mergeable_head, repository: repo)
    check_suite = create(:check_suite, head_sha: pull_request.head_sha, repository: repo, github_app: @integration, status: :completed)
    code_scanning_check_suite = create(:code_scanning_check_suite,
      pull_request_ref: pull_request.merge_ref,
      pull_request_sha: "deadbeef",
      repository: repo,
      check_suite: check_suite,
    )

    assert_equal "deadbeef", CodeScanningCheckSuite.merge_commit_for(pull_request:)
  end

  test "merge_commit_for with code scanning check suite on matching checks" do
    repo = create(:repository, from_example: :pull_request_source)
    pull_request1 = create(:pull_request, :with_mergeable_head, repository: repo)
    pull_request2 = create(:pull_request, :with_mergeable_head, repository: repo)
    check_suite = create(:check_suite, head_sha: pull_request1.head_sha, repository: repo, github_app: @integration, status: :completed)
    check_suite = create(:check_suite, head_sha: pull_request2.head_sha, repository: repo, github_app: @integration, status: :completed)
    code_scanning_check_suite = create(:code_scanning_check_suite,
      pull_request_ref: pull_request1.merge_ref,
      pull_request_sha: "deadbeef",
      repository: repo,
      check_suite: check_suite,
    )

    assert_equal "deadbeef", CodeScanningCheckSuite.merge_commit_for(pull_request: pull_request2)
  end

  test "merge_commit_for with code scanning check suite with empty pull_request_sha" do
    repo = create(:repository, from_example: :pull_request_source)
    pull_request = create(:pull_request, :with_mergeable_head, repository: repo)
    check_suite = create(:check_suite, head_sha: pull_request.head_sha, repository: repo, github_app: @integration, status: :completed)
    code_scanning_check_suite = create(:code_scanning_check_suite,
      pull_request_ref: pull_request.merge_ref,
      pull_request_sha: "",
      repository: repo,
      check_suite: check_suite,
    )

    assert_equal pull_request.merge_commit_sha, CodeScanningCheckSuite.merge_commit_for(pull_request: pull_request)
  end
end
