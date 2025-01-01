# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeConditions::PullRequestMergeConflictStateTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @owner = create(:user, login: "owner", plan: "micro")
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @pull = create(:pull_request, :with_mergeable_head, repository: @repo)
    @rando = create(:user)
  end

  test "passes when pull request has no conflicts" do
    merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :passed, merge_condition.result
    assert_nil merge_condition.message
  end

  test "fails when pull request has a merge conflict and merge_method is :merge" do
    with_enqueued_pr_sync_jobs do
      create(:commit, repository: @pull.base_repository, branch: @pull.base_ref, changes: -> (files) { files.add("foo.txt", "contents of foo base") })
      create(:commit, repository: @pull.head_repository, branch: @pull.head_ref, changes: -> (files) { files.add("foo.txt", "contents of foo head") })
    end
    @pull.reload
    @pull.create_merge_commit
    refute_nil(@pull.conflict)

    merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
    assert_equal "Pull request cannot be merged because it has a merge conflict.", merge_condition.message
  end

  test "passes when pull request has a rebase conflict and merge_method is :merge" do
    PullRequestConflict.create!(
      pull_request: @pull,
      base_sha: "0" * 40,
      head_sha: "0" * 40,
      info: "{}",
      conflict_type: :rebase_conflict
    )

    merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :passed, merge_condition.result
    assert_nil merge_condition.message
  end

  test "fails when pull request has a rebase_conflict and merge_method is :rebase" do
    PullRequestConflict.create!(
      pull_request: @pull,
      base_sha: "0" * 40,
      head_sha: "0" * 40,
      info: "{}",
      conflict_type: :rebase_conflict
    )

    merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :rebase)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
    assert_equal "Pull request cannot be merged via rebase because it has a rebase conflict.", merge_condition.message
  end

  test "fails when pull request has a merge conflict and merge_method is :rebase" do
    with_enqueued_pr_sync_jobs do
      create(:commit, repository: @pull.base_repository, branch: @pull.base_ref, changes: -> (files) { files.add("foo.txt", "contents of foo base") })
      create(:commit, repository: @pull.head_repository, branch: @pull.head_ref, changes: -> (files) { files.add("foo.txt", "contents of foo head") })
    end
    @pull.reload
    @pull.create_merge_commit
    refute_nil(@pull.conflict)

    merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :rebase)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
    assert_equal "Pull request cannot be merged because it has a merge conflict.", merge_condition.message
  end
end
