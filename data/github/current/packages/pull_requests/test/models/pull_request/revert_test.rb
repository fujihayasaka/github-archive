# typed: true
# frozen_string_literal: true

require "test_helper"

class RevertPullRequestTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @owner = create(:user, login: "ari")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: @forker, repository: @source)

    # `topic` branch has tree commits ahead of master (see test/fixtures/git/examples/pull_request_fork.git):
    #  - fb8529318277cb4dc3148ed5d0e15a61fa9d0591 (add file3)
    #  - 948a3b08cbce11ee0df1687b04defacadd11fce3 (add line 10 to file3)
    #  - 480d4f47447129f015cb327536c522ca683939a1 (add a bunch of files)
    @pull = PullRequest.create_for(@source, {
      base:  "master",
      head:  "#{@fork.user}:topic",
      user:  @issue.user,
      issue: @issue,
    })
  end

  setup do
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork
  end

  test "returns a new branch with a name based on the pull requests head branch name" do
    only = [AddToSearchIndexJob]
    success, merge_commit_sha = perform_enqueued_jobs(only: only) do
      @pull.merge(@owner, method: :merge)
    end
    assert success

    revert_ref, error = @pull.revert(@owner)
    refute error

    assert_instance_of Git::Ref, revert_ref
    assert_equal "revert-1-topic", revert_ref.name
  end

  test "returns the existing branch if a revert branch already exists" do
    only = [AddToSearchIndexJob]
    success, merge_commit_sha = perform_enqueued_jobs(only: only) do
      @pull.merge(@owner, method: :merge)
    end
    assert success

    revert_ref, error = @pull.revert(@owner)
    refute error

    assert_instance_of Git::Ref, revert_ref
    assert_equal "revert-1-topic", revert_ref.name

    revert_ref, error = @pull.revert(@owner)
    refute error

    assert_instance_of Git::Ref, revert_ref
    assert_equal "revert-1-topic", revert_ref.name
  end

  context "when reverting a normal merge" do
    test "reverts all changes" do
      original_base_tree_oid = @pull.base_repository.commits.find(@pull.current_base_sha).tree_oid

      only = [AddToSearchIndexJob]
      success, merge_commit_sha = perform_enqueued_jobs(only: only) do
        @pull.merge(@owner, method: :merge)
      end
      assert success

      revert_ref, error = @pull.revert(@owner)
      refute error

      reverted_tree_oid = revert_ref.target.tree_oid

      assert_equal original_base_tree_oid, reverted_tree_oid
    end

    test "has the new ref point to a signed commit reverting the changes introduced by the merge commit" do
      only = [AddToSearchIndexJob]
      success, merge_commit_sha = perform_enqueued_jobs(only: only) do
        @pull.merge(@owner, method: :merge)
      end
      assert success

      # Create a new unrelated commit
      base_ref = @pull.base_repository.heads.find(@pull.base_ref)
      base_commit = base_ref.append_commit({ message: "unrelated commit", committer: @owner }, @owner) do |files|
        files.add "some_file.md", "some unrelated file"
      end

      revert_ref, error = @pull.revert(@owner)
      refute error

      assert_equal "revert-1-topic", revert_ref.name

      revert_commit = revert_ref.target

      assert revert_commit.has_signature? unless GitHub.enterprise?
      assert_equal [base_commit.oid], revert_commit.parent_oids

      assert_equal "Revert \"#{@pull.title}\"", revert_commit.message
    end
  end

  context "when reverting a rebase-merge" do
    test "reverts all changes" do
      original_base_tree_oid = @pull.base_repository.commits.find(@pull.current_base_sha).tree_oid

      only = [AddToSearchIndexJob]
      success, merge_commit_sha = perform_enqueued_jobs(only: only) do
        @pull.merge(@owner, method: :rebase)
      end
      assert success

      revert_ref, error = @pull.revert(@owner)
      refute error

      reverted_tree_oid = revert_ref.target.tree_oid

      assert_equal original_base_tree_oid, reverted_tree_oid
    end

    test "creates as many unsigned revert commits as rebased commits" do
      only = [AddToSearchIndexJob]
      success, merge_commit_sha = perform_enqueued_jobs(only: only) do
        @pull.merge(@owner, method: :rebase)
      end
      assert success

      revert_ref, error = @pull.revert(@owner)
      refute error

      assert_equal "revert-1-topic", revert_ref.name

      revert_commit = revert_ref.target
      revert_parent_commit = @pull.base_repository.commits.find(revert_ref.target.first_parent_oid)
      assert_equal [merge_commit_sha], revert_parent_commit.parent_oids

      refute revert_commit.has_signature?
      refute revert_parent_commit.has_signature?

      # Reverts both commits made through the rebase
      base_ref = @pull.base_repository.heads.find(@pull.base_ref)

      second_commit = base_ref.target
      first_commit = @pull.base_repository.commits.find(second_commit.first_parent_oid)

      assert_equal <<-EOS.chomp, revert_commit.message
Revert "add line 10 to file3"

This reverts commit #{first_commit.oid}.
EOS

      assert_equal <<-EOS.chomp, revert_parent_commit.message
Revert "add a bunch of files"

This reverts commit #{second_commit.oid}.
EOS
    end

    test "returns a timeout error value if a timeout occurred" do
      only = [AddToSearchIndexJob]
      success, merge_commit_sha = perform_enqueued_jobs(only: only) do
        @pull.merge(@owner, method: :rebase)
      end
      assert success

      revert_ref, error = @pull.revert(@owner, timeout: 0.00001)

      assert_equal :timeout, error
      refute revert_ref
    end

    test "creates one signed revert commit when rebasing only one commit" do
      pull = PullRequest.create_for(@source, {
        base:  "master",
        head:  "#{@fork.user}:master-plus-one-commit", # <-- one commit to rebase
        user:  @issue.user,
        issue: @issue,
      })

      only = [AddToSearchIndexJob]
      success, merge_commit_sha = perform_enqueued_jobs(only: only) do
        pull.merge(@owner, method: :rebase)
      end
      assert success

      revert_ref, error = pull.revert(@owner)
      refute error

      assert_equal "revert-1-master-plus-one-commit", T.must(revert_ref).name

      revert_commit = T.must(revert_ref).target
      assert revert_commit.has_signature? unless GitHub.enterprise?
      assert_equal [merge_commit_sha], revert_commit.parent_oids

      assert_equal <<-EOS.chomp, revert_commit.message
Revert "add a file"

This reverts commit #{merge_commit_sha}.
EOS
    end
  end

  context "when reverting a squash-merge" do
    test "reverts all changes" do
      original_base_tree_oid = @pull.base_repository.commits.find(@pull.current_base_sha).tree_oid

      only = [AddToSearchIndexJob]
      success, merge_commit_sha = perform_enqueued_jobs(only: only) do
        @pull.merge(@owner, method: :squash)
      end
      assert success

      revert_ref, error = @pull.revert(@owner)
      refute error

      reverted_tree_oid = revert_ref.target.tree_oid

      assert_equal original_base_tree_oid, reverted_tree_oid
    end

    test "has the new ref point to a signed commit reverting the changes introduced by the squash commit" do
      only = [AddToSearchIndexJob]
      success, merge_commit_sha = perform_enqueued_jobs(only: only) do
        @pull.merge(@owner, method: :squash)
      end
      assert success

      revert_ref, error = @pull.revert(@owner)
      refute error

      assert_equal "revert-1-topic", revert_ref.name

      revert_commit = revert_ref.target

      assert revert_commit.has_signature? unless GitHub.enterprise?
      assert_equal [merge_commit_sha], revert_commit.parent_oids

      assert_equal <<-EOS.chomp, revert_commit.message
Revert "#{@pull.title} (##{@pull.number})"

This reverts commit #{merge_commit_sha}.
EOS
    end
  end

  context "reverting implicitly-merged PR" do
    test "PRs merged via something like a train are correctly revertable" do
      pr_branch = @source.refs.create("refs/heads/pr-branch", @source.default_oid, @owner)
      pr_branch.append_commit({ message: "pr branch commit", committer: @owner }, @owner) do |files|
        files.add "pr-file", "file added to pr branch"
      end
      pull = PullRequest.create_for(@source, {
        base:  "master",
        head:  "pr-branch",
        user:  @owner,
        issue: create(:issue, user: @owner, repository: @source),
      })
      master_commit = @source.default_branch_ref.append_commit({ message: "added to master", committer: @owner }, @owner) do |files|
        files.add "master-file", "file added to master"
      end
      expected_tree_oid_after_revert = master_commit.tree_oid

      # merge base into head to pick up master-file (we will later assert that
      # we don't remove it when reverting pull)
      pull.reload.merge_base_into_head(user: @owner)

      train_branch = @source.refs.create("refs/heads/train", @source.reload.default_oid, @owner)
      merge_commit_into_train, _ = train_branch.merge(@owner, "pr-branch")
      train = PullRequest.create_for(@source, {
        base:  "master",
        head:  "train",
        user:  @owner,
        issue: create(:issue, user: @owner, repository: @source),
      })

      with_enqueued_pr_sync_jobs do
        train.merge(@owner)
        assert_predicate(train, :merged?)
      end
      # component PR was merged by PullRequest#synchronize!
      assert_predicate(pull.reload, :merged?)

      # the merge into train was detected as the sha we want to keep for reverts
      assert_equal(merge_commit_into_train.oid, T.must(pull.merged_commit).oid)
      assert_equal(merge_commit_into_train.oid, pull.merge_commit_sha)

      assert pull.revertable_by?(@owner)
      revert_ref, error = pull.revert(@owner)
      refute error

      # Assert that we reverted only the changes in the train component, i.e.
      # we did not remove the file added to the master branch and then brought
      # into our branch via merge.
      assert T.must(revert_ref).target.tree_oid == expected_tree_oid_after_revert
    end

    test "octopus merge commits detected as merged event but cannot revert" do
      example_repo :octopus_merge, @source

      @source.enable_shared_storage
      @fork.enable_shared_storage

      pull = PullRequest.create_for(@source, {
        base:  "master",
        head:  "arm-one",
        user:  @owner,
        issue: create(:issue, user: @owner, repository: @source),
      })

      octo_merge_commit = @source.refs.find("branch-with-octopus-merge-on-it").target
      assert_equal(3, octo_merge_commit.parent_oids.size)

      with_enqueued_pr_sync_jobs do
        @source.refs.find("master").update(octo_merge_commit, @owner)
      end

      assert_predicate pull.reload, :merged?
      assert_equal(octo_merge_commit, pull.merged_commit)
      exception = assert_raises(PullRequest::RevertError) do
        pull.revert(@owner)
      end
      assert_equal("cannot handle octopus merges (#{pull.id})", exception.message)
    end

    test "mainline-as-right-parent merge commits detected as merged event but cannot revert" do
      example_repo :merge_with_right_mainline, @source

      @source.enable_shared_storage
      @fork.enable_shared_storage

      pull = PullRequest.create_for(@source, {
        base:  "master",
        head:  "topic",
        user:  @owner,
        issue: create(:issue, user: @owner, repository: @source),
      })
      merge_commit = @source.refs.find("after-merge").target

      with_enqueued_pr_sync_jobs do
        @source.refs.find("master").update(merge_commit, @owner)
      end
      assert_predicate pull.reload, :merged?
      assert_equal(merge_commit.oid, pull.events.merges.last.commit_id)
      assert_nil(pull.merged_commit) # because of the assumption in Commit#merged_from?
      result, error = pull.revert(@owner)
      assert_equal(:not_revertable, error)
    end
  end
end
