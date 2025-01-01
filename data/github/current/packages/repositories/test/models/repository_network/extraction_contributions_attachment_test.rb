# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class ExtractionContributionsAttachmentTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, plan: "medium")
    @repo  = create(:private_repository, owner: @owner, from_example: :forkable)
    @repo.allow_private_repository_forking(actor: @owner)

    @repos = Array.new(4) do
      user = create(:user, plan: "micro")
      @repo.add_member user
      fork = create(:fork_repository, fork_repo: @repo, forker: user)
    end

    @fork = @repos.first
    user = create(:user).tap { |u| @fork.add_member u }

    @forkfork = create(:fork_repository, fork_repo: @fork, forker: user)
    @repos << @forkfork

    @repos.last.update_attribute :pushed_at, Time.now + 100000

    @network = @repo.reload_network

    @repo2 = create(:repository)
    @network2 = @repo2.network

    @user = create(:user, plan: "micro")
    @user_repo = create(:private_repository, owner: @user, from_example: :forkable)
    @user_repo.allow_private_repository_forking(actor: @user)
    @user2 = create(:user, plan: "micro")
    @user3 = create(:user, plan: "micro")
    @user_repo.add_member @user2
    @user_repo.add_member @user3
    @user2_fork = create(:fork_repository, fork_repo: @user_repo, forker: @user2)

    @user3_fork = create(:fork_repository, fork_repo: @user2_fork, forker: @user3)

    example_repo_snapshot(snapshot_spokesdb: true)
  end

  setup do
    example_repo_restore
  end

  test "detaching a repository backfills commit contributions" do
    metadata = { message: "blah", committer: @fork.owner }
    @fork.heads.find("master").append_commit(metadata, @fork.owner) do |files|
      files.add("blah", "blah")
    end

    @fork.reload

    assert_equal 0, CommitContributions.domain.commit_count_for_repository(@fork)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, ContributionsBackfillJob]) do
      @fork.detach!
    end

    @fork.reload

    refute_equal 0, CommitContributions.domain.commit_count_for_repository(@fork)
    DGit.check_replicas @fork
  end

  test "reattaching a repository deletes its commit contributions" do
    metadata = { message: "blah", committer: @fork.owner }
    @fork.heads.find("master").append_commit(metadata, @fork.owner) do |files|
      files.add("blah", "blah")
    end

    @fork.reload
    assert_equal 0, CommitContributions.domain.commit_count_for_repository(@fork)

    only = [AddToSearchIndexJob, RemoveFromSearchIndexJob, RepositoryOrchestrationJob, ContributionsBackfillJob]
    perform_enqueued_jobs(only: only) do
      @fork.detach!
    end

    @fork.reload
    refute @fork.fork?

    refute_equal 0, CommitContributions.domain.commit_count_for_repository(@fork)
    DGit.check_replicas @fork

    only = [AddToSearchIndexJob, RemoveFromSearchIndexJob, RepositoryOrchestrationJob]
    perform_enqueued_jobs(only: only) do
      @fork.reattach!
    end

    @fork.reload
    assert @fork.fork?

    assert_equal 0, CommitContributions.domain.commit_count_for_repository(@fork)
    DGit.check_replicas @fork
  end

  test "detaching the root should leave the root commit contributions and backfill the new elected root" do
    assert @repo.network_root?
    old_network = @repo.network

    metadata = { message: "blah", committer: @repo.owner }
    @repo.heads.find("master").append_commit(metadata, @repo.owner) do |files|
      files.add("blah", "blah")
    end

    CommitContribution.backfill!(@repo)
    @repo.reload
    refute_equal 0, CommitContributions.domain.commit_count_for_repository(@repo)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @repo.detach!
    end
    assert_enqueued_jobs 1, only: ContributionsBackfillJob, queue: "contributions_backfill"

    @repo.reload
    old_network.reload

    refute_equal old_network, @repo.network
    refute_equal 0, CommitContributions.domain.commit_count_for_repository(@repo)

    elected_root = old_network.root
    refute_equal elected_root, @repo

    assert_enqueued_with(job: ContributionsBackfillJob, args: [elected_root.id, false], queue: "contributions_backfill")
    DGit.check_replicas @repo
  end
end
