# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestHeadRefCleanupTest < GitHub::TestCase
  setup do
    @source = create(:repository, from_example: :pull_request_source)
    @owner  = @source.owner

    @forker = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @contributor  = create(:user)
    @fork.add_member @contributor, action: :write
  end

  def create_cross_repo_pull
    PullRequest.create_for!(@source,
      user: @forker,
      base: "#{@owner.login}:master",
      head: "#{@forker.login}:topic",
      title: "cross repo pull",
      body: "blah")
  end

  def create_same_repo_pull
    PullRequest.create_for!(@fork,
      user: @forker,
      base: "#{@forker.login}:master",
      head: "#{@forker.login}:topic",
      title: "same repo pull",
      body: "blah")
  end

  test "open same-repo pull requests can't delete the head ref" do
    pull = create_same_repo_pull

    refute pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "open cross-repo pull requests can't delete the head ref" do
    pull = create_cross_repo_pull

    refute pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "closed but unmerged same-repo pull requests can't delete the head ref safely" do
    pull = create_same_repo_pull
    pull.close
    assert pull.closed?

    refute pull.head_ref_safely_deleteable_by?(@forker)
    assert pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "closed but unmerged cross-repo pull requests can't delete the head ref safely" do
    pull = create_cross_repo_pull
    pull.close
    assert pull.closed?

    refute pull.head_ref_safely_deleteable_by?(@forker)
    assert pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "merged same-repo pull requests can delete the head ref safely" do
    pull = create_same_repo_pull
    assert pull.merge.first

    assert pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "merged cross-repo pull requests can delete the head ref safely" do
    pull = create_cross_repo_pull
    assert pull.merge.first

    assert pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "can't delete the head ref without push access to head_repository of a same-repo pull" do
    pull = create_same_repo_pull

    refute pull.head_ref_safely_deleteable_by?(@owner)
    refute pull.head_ref_unsafely_deleteable_by?(@owner)
  end

  test "can't delete the head ref without push access to head_repository of a cross-repo pull" do
    pull = create_cross_repo_pull

    refute pull.head_ref_safely_deleteable_by?(@owner)
    refute pull.head_ref_unsafely_deleteable_by?(@owner)
  end

  test "merged same-repo pull requests with additional commits can't delete head_ref at all" do
    pull = create_same_repo_pull
    assert pull.merge.first

    metadata = { message: "test commit", committer: @forker }
    ref = @fork.heads.find(pull.head_ref)
    ref.append_commit(metadata, @forker) {}

    refute pull.head_ref_deleteable_by?(@forker)
    refute pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "merged cross-repo pull requests with additional commits can't delete head_ref at all" do
    pull = create_cross_repo_pull
    assert pull.merge.first

    metadata = { message: "test commit", committer: @forker }
    ref = @fork.heads.find(pull.head_ref)
    ref.append_commit(metadata, @forker) {}

    refute pull.head_ref_deleteable_by?(@forker)
    refute pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "closed same-repo pull requests with additional commits can't delete head_ref at all" do
    pull = create_same_repo_pull
    pull.close
    assert pull.closed?

    metadata = { message: "test commit", committer: @forker }
    ref = @fork.heads.find(pull.head_ref)
    ref.append_commit(metadata, @forker) {}

    refute pull.head_ref_deleteable_by?(@forker)
    refute pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "closed cross-repo pull requests with additional commits can't delete head_ref at all" do
    pull = create_cross_repo_pull
    pull.close
    assert pull.closed?

    metadata = { message: "test commit", committer: @forker }
    ref = pull.head_repository.heads.find(pull.head_ref)
    ref.append_commit(metadata, @forker) {}

    refute pull.head_ref_deleteable_by?(@forker)
    refute pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "can't delete the default branch for the head repo of a same-repo pull" do
    pull = create_same_repo_pull
    assert pull.merge.first

    pull.head_repository.update!(default_branch: pull.head_ref_name)

    refute pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "can't delete the default branch for the head repo of a cross-repo pull" do
    pull = create_cross_repo_pull
    assert pull.merge.first

    pull.head_repository.update!(default_branch: pull.head_ref_name)

    refute pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "with a missing base ref" do
    pull = create_same_repo_pull

    assert pull.merge.first

    base_repo = pull.base_repository
    base_repo.heads.find(pull.base_ref).delete(base_repo.owner)

    refute base_repo.heads.exist?(pull.base_ref)

    pull.reload

    assert pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  test "when the PR's commits have been merged while the PR is closed" do
    pull = create_same_repo_pull
    pull.close  # the merge won't be detected for a closed PR
    assert pull.closed?

    base_repo = pull.base_repository
    base_ref  = base_repo.heads.find(pull.base_ref)

    base_ref.update(pull.head_sha, base_repo.owner)

    pull.reload

    assert pull.closed?
    refute pull.merged?

    assert pull.head_ref_safely_deleteable_by?(@forker)
    refute pull.head_ref_unsafely_deleteable_by?(@forker)
  end

  context "when the head ref is locked for everyone" do
    test "head ref is not deletable by non-admins" do
      pull = create_cross_repo_pull
      @fork.protect_branch(
        pull.head_ref,
        creator: @forker,
        block_deletions: false,
        lock_branch: true,
        enforce_admins: true,
        entry_point: :test_case,
      )
      assert pull.merge.first

      refute pull.head_ref_safely_deleteable_by?(@contributor)
      refute pull.head_ref_unsafely_deleteable_by?(@contributor)
    end

    test "head ref is not deleteable by admins" do
      pull = create_cross_repo_pull
      @fork.protect_branch(
        pull.head_ref,
        creator: @forker,
        block_deletions: false,
        lock_branch: true,
        enforce_admins: true,
        entry_point: :test_case,
      )
      assert pull.merge.first

      refute pull.head_ref_safely_deleteable_by?(@forker)
      refute pull.head_ref_unsafely_deleteable_by?(@forker)
    end
  end

  context "when the head ref is locked for non-admins" do
    test "head ref is not deletable by non-admins" do
      pull = create_cross_repo_pull
      @fork.protect_branch(
        pull.head_ref,
        creator: @forker,
        block_deletions: false,
        lock_branch: true,
        entry_point: :test_case,
      )
      assert pull.merge.first

      refute pull.head_ref_safely_deleteable_by?(@contributor)
      refute pull.head_ref_unsafely_deleteable_by?(@contributor)
    end

    test "head ref is safely deleteable by admins" do
      pull = create_cross_repo_pull
      @fork.protect_branch(
        pull.head_ref,
        creator: @forker,
        block_deletions: false,
        lock_branch: true,
        entry_point: :test_case,
      )
      assert pull.merge.first

      assert pull.head_ref_safely_deleteable_by?(@forker)
      refute pull.head_ref_unsafely_deleteable_by?(@forker)
    end
  end

end
