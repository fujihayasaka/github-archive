# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestUpdateBaseOfDependentPrsTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  setup do
    Spokesd.enable_spokesd

    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :pull_request_source)

    @pull = PullRequest.create_for(@repo, {
      base:  "master",
      head:  "master-forward-2",
      user:  @user,
      issue: create(:issue, user: @user, repository: @repo),
    })

    base_ref = @repo.heads.find("master-forward-2")
    head_ref = @repo.heads.create("master-forward-3", base_ref.target_oid, @repo.owner)

    head_ref.append_commit({ message: "test", committer: @repo.owner }, @repo.owner) do |files|
      files.add("test.txt", "test")
    end

    @dependent_pr = PullRequest.create_for!(@repo,
      user: @repo.owner,
      base: "master-forward-2",
      head: "master-forward-3",
      issue: create(:issue, user: @user, repository: @repo),
    )

    head_ref = @repo.heads.create("master-forward-3-1", base_ref.target_oid, @repo.owner)

    head_ref.append_commit({ message: "test", committer: @repo.owner }, @repo.owner) do |files|
      files.add("test.txt", "test")
    end

    @dependent_pr2 = PullRequest.create_for!(@repo,
      user: @repo.owner,
      base: "master-forward-2",
      head: "master-forward-3-1",
      issue: create(:issue, user: @user, repository: @repo),
    )

    @pull.mark_as_merged
  end

  test "doesn't update PRs if the depended-on PR isn't merged" do
    @pull.update_attribute(:merged_at, nil)

    refute @pull.merged?

    refute @pull.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal @dependent_pr.reload.base_ref, "master-forward-2"
  end

  test "doesn't update PRs if the head branch is default" do
    @pull.head_repository.default_branch = @pull.head_ref

    assert @pull.head_is_default_branch?

    refute @pull.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal @dependent_pr.reload.base_ref, "master-forward-2"
  end

  test "doesn't update PRs if the head branch is protected" do
    create(:protected_branch, repository: @pull.head_repository, name: @pull.head_ref_name)

    assert @pull.head_is_protected_branch?

    refute @pull.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal @dependent_pr.reload.base_ref, "master-forward-2"
  end

  test "updates PRs if the head branch is protected but allows deletion" do
    create(:protected_branch, repository: @pull.head_repository, name: @pull.head_ref_name, block_deletions_enforcement_level: "off")

    assert @pull.head_is_protected_branch?

    assert @pull.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal @dependent_pr.reload.base_ref, "master"
  end

  test "doesn't update PRs if the head branch allows deletion but is locked" do
    create(:protected_branch, repository: @pull.head_repository, name: @pull.head_ref_name, block_deletions_enforcement_level: "everyone", lock_branch_enforcement_level: "everyone")

    assert @pull.head_is_protected_branch?

    refute @pull.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal @dependent_pr.reload.base_ref, "master-forward-2"
  end

  test "doesn't update PRs if open PRs exceeds limit" do
    PullRequest.stub_const(:AUTO_CHANGE_BASE_MAX_PULL_REQUESTS, 1) do
      refute @pull.send(:update_base_of_dependent_prs, actor: @user)

      assert_equal @dependent_pr.reload.base_ref, "master-forward-2"
      assert_equal @dependent_pr2.reload.base_ref, "master-forward-2"
    end
  end

  test "doesn't update PRs if there's an existing ref pair" do
    PullRequest.create_for!(@repo,
      user: @repo.owner,
      base: "master",
      head: "master-forward-3",
      issue: create(:issue, user: @user, repository: @repo)
    )

    refute @pull.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal @dependent_pr.reload.base_ref, "master-forward-2"
  end

  test "doesn't update PRs if head_ref would be the same as the new base ref" do
    head_ref = @repo.heads.find("master")
    head_ref.append_commit({ message: "test", committer: @repo.owner }, @repo.owner) do |files|
      files.add("test.txt", "test")
    end

    circular_pull = PullRequest.create_for!(@repo,
      user: @repo.owner,
      base: "master-forward-2",
      head: "master",
      issue: create(:issue, user: @user, repository: @repo)
    )

    assert @pull.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal circular_pull.reload.base_ref, "master-forward-2"
  end

  test "creates an issue event when the base update fails" do
    PullRequest.create_for!(@repo,
      user: @repo.owner,
      base: "master",
      head: "master-forward-3",
      issue: create(:issue, user: @user, repository: @repo)
    )

    refute @pull.send(:update_base_of_dependent_prs, actor: @user)

    failed_event = @dependent_pr.issue.events.where(event: :automatic_base_change_failed).last
    refute_nil failed_event

    assert_equal failed_event.title_was, "master-forward-2"
    assert_equal failed_event.title_is, "master"
    assert_equal failed_event.message, PullRequest::RefPairingAlreadyExistsError.error_type_key
  end

  test "auto-merges when the comparison after base change would be empty" do
    pull = PullRequest.create_for(@repo, {
      base:  "master",
      head:  "master-forward-2",
      user:  @user,
      issue: create(:issue, user: @user, repository: @repo),
    })

    @repo.update_merge_settings(@repo.owner, delete_branch_allowed: true)
    assert_predicate @repo, :delete_branch_on_merge?

    base_ref = @repo.heads.find("master-forward-3")
    head_ref = @repo.heads.create("master-forward-4", base_ref.target_oid, @repo.owner)
    expected_merge_base_after_update = base_ref.sha

    expected_commits_after_update = []
    expected_commits_after_update << head_ref.append_commit({ message: "test", committer: @repo.owner }, @repo.owner) do |files|
      files.add("test.txt", "test test")
    end
    expected_commits_after_update << head_ref.append_commit({ message: "test", committer: @repo.owner }, @repo.owner) do |files|
      files.add("test.txt", "test test test")
    end

    double_dependent_pr = PullRequest.create_for!(@repo,
      user: @repo.owner,
      base: "master-forward-3",
      head: "master-forward-4",
      issue: create(:issue, user: @user, repository: @repo),
    )

    base_ref = @repo.heads.find("master-forward-4")
    head_ref = @repo.heads.create("master-forward-5", base_ref.target_oid, @repo.owner)

    head_ref.append_commit({ message: "test", committer: @repo.owner }, @repo.owner) do |files|
      files.add("test.txt", "test test test test")
    end

    triple_dependent_pr = PullRequest.create_for!(@repo,
      user: @repo.owner,
      base: "master",
      head: "master-forward-5",
      issue: create(:issue, user: @user, repository: @repo),
    )

    with_enqueued_pr_sync_jobs(additional_jobs: [PullRequests::CleanupHeadRefJob]) do
      merged, _ = triple_dependent_pr.merge
      assert merged
    end

    # pull should be auto-merged because triple_dependent_pr, which
    # contains pull's commits, was merged into pull's base branch.
    assert_predicate pull.reload, :merged?

    # and its head ref should be cleaned up.
    refute @repo.heads.read("master-forward-2").exist?

    @dependent_pr.reload

    # @dependent_pr should have become merged when pull auto-updated the base
    # of its dependent PRs.
    assert_predicate @dependent_pr, :merged?

    # and @dependent_pr's base should have been auto-updated, despite an empty comparison
    assert_equal @dependent_pr.base_ref, "master"
    succeeded_event = @dependent_pr.issue.events.where(event: :automatic_base_change_succeeded).last
    refute_nil succeeded_event

    # and the succeeded event should precede the merged event
    merged_event = @dependent_pr.issue.events.where(event: :merged).last
    assert succeeded_event.id < merged_event.id

    # and its head ref should be cleaned up.
    refute @repo.heads.read("master-forward-3").exist?

    double_dependent_pr.reload

    # double_dependent_pr should have become merged when @dependent_pr auto-updated the base
    assert_predicate double_dependent_pr, :merged?

    # and double_dependent_pr's base should have been auto-updated, despite an empty comparison
    assert_equal double_dependent_pr.base_ref, "master"
    succeeded_event = double_dependent_pr.issue.events.where(event: :automatic_base_change_succeeded).last
    refute_nil succeeded_event

    # and the succeeded event should precede the merged event
    merged_event = double_dependent_pr.issue.events.where(event: :merged).last
    assert succeeded_event.id < merged_event.id

    # and it should still have two commits in its comparison
    assert_equal expected_merge_base_after_update, double_dependent_pr.merge_base
    assert_equal expected_commits_after_update, double_dependent_pr.historical_comparison.commits, "expected to have preserved the pull's diff"

    # and its head ref should be cleaned up.
    refute @repo.heads.read("master-forward-4").exist?
  end

  test "updates dependent PRs" do
    assert @pull.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal @dependent_pr.reload.base_ref, "master"
    assert_equal @dependent_pr2.reload.base_ref, "master"
  end

  test "creates an issue event when the base update succeeds" do
    assert @pull.send(:update_base_of_dependent_prs, actor: @user)

    succeeded_event = @dependent_pr.issue.events.where(event: :automatic_base_change_succeeded).last
    refute_nil succeeded_event

    assert_equal succeeded_event.title_was, "master-forward-2"
    assert_equal succeeded_event.title_is, "master"
  end

  test "a pull in the parent does not update cross-repo PRs from forks" do
    fork_repo = create(:fork_repository, forker: create(:user), fork_repo: @repo, from_example: :pull_request_source)

    fork_base_ref = fork_repo.heads.find("master-forward-2")
    fork_head_ref = fork_repo.heads.create("master-forward-fork", fork_base_ref.target_oid, fork_repo.owner)

    fork_head_ref.append_commit({ message: "Contribution!", committer: fork_repo.owner }, fork_repo.owner) do |files|
      files.add("spork.txt", "content")
    end

    cross_repo_pr = PullRequest.create_for!(@repo,
      user: fork_repo.owner,
      base: "#{@repo.owner}:master-forward-2",
      head: "#{fork_repo.owner}:master-forward-fork",
      issue: create(:issue, user: fork_repo.owner, repository: @repo),
    )

    assert @pull.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal @dependent_pr.reload.base_ref, "master"
    assert_equal @dependent_pr2.reload.base_ref, "master"

    assert_equal cross_repo_pr.reload.base_ref, "master-forward-2"
  end

  test "a pull in the parent does not update same-repo PRs in forks with matching ref names" do
    fork_repo = create(:fork_repository, forker: create(:user), fork_repo: @repo, from_example: :pull_request_source)

    fork_base_ref = fork_repo.heads.find("master-forward-2")
    fork_head_ref = fork_repo.heads.create("master-forward-fork", fork_base_ref.target_oid, fork_repo.owner)

    fork_head_ref.append_commit({ message: "Contribution!", committer: fork_repo.owner }, fork_repo.owner) do |files|
      files.add("spork.txt", "content")
    end

    fork_dependent_pr = PullRequest.create_for!(fork_repo,
      user: fork_repo.owner,
      base: "master-forward-2",
      head: "master-forward-fork",
      issue: create(:issue, user: fork_repo.owner, repository: fork_repo),
    )

    assert @pull.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal @dependent_pr.reload.base_ref, "master"
    assert_equal @dependent_pr2.reload.base_ref, "master"

    assert_equal fork_dependent_pr.reload.base_ref, "master-forward-2"
  end

  test "a cross-repo PR does not update PRs in the head repo with a matching base ref name" do
    fork_repo = create(:fork_repository, forker: create(:user), fork_repo: @repo, from_example: :pull_request_source)

    cross_repo_pr = PullRequest.create_for!(@repo,
      user: fork_repo.owner,
      base: "#{@repo.owner}:master",
      head: "#{fork_repo.owner}:master-forward-2",
      issue: create(:issue, user: fork_repo.owner, repository: @repo),
    )

    fork_base_ref = fork_repo.heads.find("master-forward-2")
    fork_head_ref = fork_repo.heads.create("master-forward-3", fork_base_ref.target_oid, fork_repo.owner)

    fork_head_ref.append_commit({ message: "Contribution!", committer: fork_repo.owner }, fork_repo.owner) do |files|
      files.add("spork.txt", "content")
    end

    fork_dependent_pr = PullRequest.create_for!(fork_repo,
      user: fork_repo.owner,
      base: "master-forward-2",
      head: "master-forward-3",
      issue: create(:issue, user: fork_repo.owner, repository: fork_repo),
    )

    refute cross_repo_pr.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal "master-forward-2", fork_dependent_pr.reload.base_ref
  end

  test "a cross-repo PR does not update PRs in the base repo with a matching base ref name" do
    fork_repo = create(:fork_repository, forker: create(:user), fork_repo: @repo, from_example: :pull_request_source)

    fork_dependent_pr = PullRequest.create_for!(@repo,
      user: fork_repo.owner,
      base: "#{@repo.owner}:master",
      head: "#{fork_repo.owner}:master-forward-2",
      issue: create(:issue, user: fork_repo.owner, repository: @repo),
    )

    refute fork_dependent_pr.send(:update_base_of_dependent_prs, actor: @user)

    assert_equal "master-forward-2", @dependent_pr.reload.base_ref
    assert_equal "master-forward-2", @dependent_pr2.reload.base_ref
  end
end
