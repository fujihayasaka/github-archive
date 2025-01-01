# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMergeBaseIntoHeadTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @ari = create(:user, login: "ari")
    @source = create(:repository, owner: @ari, from_example: :pull_request_source)
    @bwalsh = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @bwalsh, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: @bwalsh, repository: @source)
    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
  end

  setup do
    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    @pull.create_merge_commit

    reset_cache
  end

  def commit_to_repo(repo, branch: "master", filename: "README.txt", content: nil)
    metadata = { message: "commit", committer: repo.owner }

    ref = repo.heads.find(branch)
    ref.append_commit(metadata, repo.owner) do |files|
      files.add(filename, content || "test content at #{Time.now.to_f}")
    end

    refute_nil ref.target_oid
    ref.target_oid
  end

  test "merging head brings branch ahead of base" do
    assert_predicate @pull, :behind_base?
    assert_equal :clean, @pull.merge_state.status
    assert old_head_sha = @pull.head_sha

    assert_predicate @pull.updateability.check_mergeability(@bwalsh), :success?

    with_enqueued_pr_sync_jobs do
      @pull.merge_base_into_head(user: @bwalsh)
    end
    @pull.reload

    refute_predicate @pull, :behind_base?
    assert_equal :unknown, @pull.merge_state.status
    refute_equal old_head_sha, @pull.head_sha
  end

  test "merge without head repository permissions raises an exception" do
    refute @fork.pushable_by?(@ari)

    can_merge_result = @pull.updateability.check_mergeability(@ari)
    refute_predicate can_merge_result, :success?
    assert_equal "You don’t have write access to bwalsh:topic.", can_merge_result.failure_reason

    assert_raises PullRequest::PermissionError do
      @pull.merge_base_into_head(user: @ari)
    end
  end

  test "merge with conflict raises an exception" do
    with_enqueued_pr_sync_jobs do
      commit_to_repo(@source, branch: "master", filename: "README.txt", content: "a")
      commit_to_repo(@fork, branch: "topic", filename: "README.txt", content: "b")
    end
    @pull.reload
    refute @pull.mergeable?

    can_merge_result = @pull.updateability.check_mergeability(@bwalsh)
    refute_predicate can_merge_result, :success?
    assert_equal "This branch has conflicts with the base branch.", can_merge_result.failure_reason

    assert_raises PullRequest::MergeConflictError do
      @pull.merge_base_into_head(user: @bwalsh)
    end
  end

  test "merge with expected head ref difference raises an exception" do
    expected_head_oid = @pull.head_sha

    with_enqueued_pr_sync_jobs do
      commit_to_repo(@fork, branch: "topic", filename: "README.txt", content: "b")
    end
    @pull.reload
    refute_equal expected_head_oid, @pull.head_sha

    assert_raises PullRequest::RefMismatch do
      @pull.merge_base_into_head(user: @bwalsh, expected_head_oid: expected_head_oid)
    end
  end

  test "merge committer is GitHub and author is user" do
    with_enqueued_pr_sync_jobs do
      @pull.merge_base_into_head(user: @bwalsh)
    end
    @pull.reload

    merge = @pull.head_repository.commits.find(@pull.head_sha)

    assert_equal merge.author_name, @bwalsh.git_author_name
    assert_equal merge.author_email, @bwalsh.git_author_email
    assert_equal merge.committer_name, GitHub.web_committer_name
    assert_equal merge.committer_email, GitHub.web_committer_email
  end
end
