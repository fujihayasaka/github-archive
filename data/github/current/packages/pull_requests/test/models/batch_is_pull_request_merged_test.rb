# typed: true
# frozen_string_literal: true

require "test_helper"

class BatchIsPullRequestMergedTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  include PullRequestSynchronizationTestHelpers

  fixtures do
    @fork_parent_repo, @fork_child_repo = make_repos

    @fork_parent_repo.enable_shared_storage
    @fork_child_repo.enable_shared_storage

    @pull = make_pr(@fork_parent_repo, @fork_child_repo)

    @base_repo = @pull.base_repository
    @head_repo = @pull.head_repository

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    Spokesd.enable_spokesd
  end

  test "doesn't batch precompute if there is only one PR" do
    ref = @base_repo.refs.read("refs/heads/master")
    master_before = ref.target_oid
    master_after = @pull.head_sha

    ref.update(master_after, @base_repo.owner)
    ref_update = PullRequest::RefUpdate.new(
      repository: @base_repo,
      pusher: @base_repo.owner,
      qualified_refname: "refs/heads/master",
      before_oid: master_before,
      after_oid: master_after
    )
    result = BatchIsPullRequestMerged.call(ref_update:)

    # Doesn't precompute a single PR, instead returns EmptyResult
    assert_equal result, BatchIsPullRequestMerged::EmptyResult

    # What if there are two PR's?
    user = @base_repo.owner.owner
    metadata = { message: "msg", committer: user }
    other_head_ref = @pull.head_repository.heads.create("other_topic", master_before, user)
    pr_commit = other_head_ref.append_commit(metadata, user) { |f| f.add "file1", "1" }

    @other_pull = make_pr(@pull.base_repository, @pull.head_repository, branch: "other_topic")

    ref_update = PullRequest::RefUpdate.new(
      repository: @base_repo,
      pusher: @base_repo.owner,
      qualified_refname: "refs/heads/master",
      before_oid: master_before,
      after_oid: master_after
    )
    result = BatchIsPullRequestMerged.call(ref_update:)

    # This result should contain precomputed merged values
    refute_equal result, BatchIsPullRequestMerged::EmptyResult

    assert_equal(
      true,
      result.fetch(base_oid: master_after, head_oid: @pull.head_sha),
      "expected @pull to be marked as 'merged'"
    )

    assert_equal(
      false,
      result.fetch(base_oid: master_after, head_oid: @other_pull.head_sha),
      "expected @other_pull to be marked as 'not merged'"
    )
  end

  # Test all 12 permutations of intra- and inter-repo PRs:
  #
  #   ( PR from fork parent to child  |  PR from fork child to parent  |  PR within same repo )
  # × ( base ref update causes sync  |  head ref update causes sync                           )
  # × ( head ref still has unmerged commits  |  head ref is merged                            )
  [[:parent, :child], [:child, :parent], [:repo, :self]].each do |base_repo_name, head_repo_name|
    context "PR from #{head_repo_name} to #{base_repo_name}" do
      test "base ref is updated, head ref has unmerged commits" do
        case base_repo_name
        when :parent
          base_repo = @fork_parent_repo
          head_repo = @fork_child_repo
        when :child
          base_repo = @fork_child_repo
          head_repo = @fork_parent_repo
        when :repo
          base_repo = @fork_parent_repo
          head_repo = @fork_parent_repo
        end

        user = base_repo.owner
        metadata = { message: "msg", committer: user }

        # Add a head branch and an initial commit for the PR
        head_ref = head_repo.heads.create("pr_head", head_repo.heads["master"].target_oid, user)
        pr_commit = head_ref.append_commit(metadata, user) { |f| f.add "file1", "1" }
        base_repo.fetch_commits_from_network(head_repo, pr_commit.oid)

        # Create the PR
        pull = make_pr(base_repo, head_repo, branch: "pr_head")

        # Update base branch
        base_ref = base_repo.heads["master"]
        with_enqueued_pr_sync_jobs do
          base_ref.append_commit(metadata, user) { |f| f.add "file2", "2" }
        end

        # PR should still be open
        refute pull.reload.issue.closed?
      end

      test "base ref is updated, head ref has no unmerged commits" do
        case base_repo_name
        when :parent
          base_repo = @fork_parent_repo
          head_repo = @fork_child_repo
        when :child
          base_repo = @fork_child_repo
          head_repo = @fork_parent_repo
        when :repo
          base_repo = @fork_parent_repo
          head_repo = @fork_parent_repo
        end

        user = base_repo.owner
        metadata = { message: "msg", committer: user }

        # Add a head branch and an initial commit for the PR
        head_ref = head_repo.heads.create("pr_head", head_repo.heads["master"].target_oid, user)
        pr_commit = head_ref.append_commit(metadata, user) { |f| f.add "file1", "1" }
        base_repo.fetch_commits_from_network(head_repo, pr_commit.oid)

        # Create the PR
        pull = make_pr(base_repo, head_repo, branch: "pr_head")

        # Create a merge commit
        merge_commit_oid = pull.create_merge_commit

        # Update base branch
        base_ref = base_repo.heads["master"]
        with_enqueued_pr_sync_jobs do
          base_ref.update(merge_commit_oid, user)
        end

        # PR should be closed
        assert pull.reload.issue.closed?
      end

      test "head ref is updated, updated head ref has unmerged commits" do
        case base_repo_name
        when :parent
          base_repo = @fork_parent_repo
          head_repo = @fork_child_repo
        when :child
          base_repo = @fork_child_repo
          head_repo = @fork_parent_repo
        when :repo
          base_repo = @fork_parent_repo
          head_repo = @fork_parent_repo
        end

        user = base_repo.owner
        metadata = { message: "msg", committer: user }

        # Add a head branch and an initial commit for the PR
        head_ref = head_repo.heads.create("pr_head", head_repo.heads["master"].target_oid, user)
        pr_commit = head_ref.append_commit(metadata, user) { |f| f.add "file1", "1" }
        base_repo.fetch_commits_from_network(head_repo, pr_commit.oid)

        # Create the PR
        pull = make_pr(base_repo, head_repo, branch: "pr_head")

        # Update head branch
        with_enqueued_pr_sync_jobs do
          head_ref.append_commit(metadata, user) { |f| f.add "file2", "2" }
        end

        # PR should still be open
        refute pull.reload.issue.closed?
      end

      test "head ref is updated, updated head ref has no unmerged commits" do
        case base_repo_name
        when :parent
          base_repo = @fork_parent_repo
          head_repo = @fork_child_repo
        when :child
          base_repo = @fork_child_repo
          head_repo = @fork_parent_repo
        when :repo
          base_repo = @fork_parent_repo
          head_repo = @fork_parent_repo
        end

        user = base_repo.owner
        metadata = { message: "msg", committer: user }

        # Add a head branch and an initial commit for the PR
        head_ref = head_repo.heads.create("pr_head", head_repo.heads["master"].target_oid, user)
        pr_commit_1 = head_ref.append_commit(metadata, user) { |f| f.add "file1", "1" }
        base_repo.fetch_commits_from_network(head_repo, pr_commit_1.oid)

        # Create the PR
        pull = make_pr(base_repo, head_repo, branch: "pr_head")

        # Create a merge commit
        merge_commit_oid = pull.create_merge_commit

        # Add another commit to head branch
        pr_commit_2 = head_ref.append_commit(metadata, user) { |f| f.add "file2", "2" }
        base_repo.fetch_commits_from_network(head_repo, pr_commit_2.oid)

        # Update base branch to merge, but pr_commit_2 is still not in master so PR stays open
        base_ref = base_repo.heads["master"]
        with_enqueued_pr_sync_jobs do
          base_ref.update(merge_commit_oid, user)
        end

        # PR should be open
        refute pull.reload.issue.closed?

        # Now force-push the head branch back to pr_commit_1, which is contained in master
        with_enqueued_pr_sync_jobs do
          head_ref.update(pr_commit_1.oid, user)
        end

        # PR should be closed
        assert pull.reload.issue.closed?
      end
    end
  end
end
