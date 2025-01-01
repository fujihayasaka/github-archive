# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestAdvisoryWorkspaceTest < GitHub::TestCase
  fixtures do
    @actor = create(:user)
    @org = create(:organization, admin: @actor)
    @repo = create(:repository, owner: @org, from_example: :simple)

    @advisory = create(:repository_advisory, repository: @repo, author: @actor)

    only = [RepositoryCloneJob]
    @workspace_repo = perform_enqueued_jobs(only: only) do
      GitHub.context.push(actor_id: @actor.id)
      RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @actor).tap(&:save!).tap(&:reload)
    end

    ref = @workspace_repo.heads.find("master")
    ref.append_commit({ message: "blah", committer: @actor }, @actor) do |files|
      files.add("README.md", "change")
    end

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    @pull_request = PullRequest.new(
      repository:      @workspace_repo,
      base_repository: @repo,
      base_user:       @repo.owner,
      base_ref:        "master",
      head_repository: @workspace_repo,
      head_user:       @workspace_repo.owner,
      head_ref:        "master",
      issue:           create(:issue, user: @actor, repository: @workspace_repo),
      user:            @actor,
    )

    assert_predicate @pull_request, :valid?
  end

  test "allows creating a pull request targeting the base repo" do
    @pull_request.save!

    assert_predicate @pull_request, :persisted?
  end

  test "pull request has one commit" do
    @pull_request.save!

    assert_equal 1, @pull_request.total_commits
  end

  test "pull request diff changes one file" do
    @pull_request.save!

    assert_predicate @pull_request, :diff_available?
    assert_equal 1, @pull_request.changed_files
    assert_equal ["README.md"], @pull_request.diffs.entries.map(&:path)
  end

  test "allows only pull requests in advisory workspace that have origin repository as base" do
    @pull_request.base_repository = @workspace_repo

    refute_predicate @pull_request, :valid?
    refute_empty @pull_request.errors[:base_ref]
  end

  test "allows only pull requests in advisory workspace that have itself as head" do
    @pull_request.head_repository = @repo

    refute_predicate @pull_request, :valid?
    refute_empty @pull_request.errors[:head_ref]
  end

  test "successfully creates merge commit when base branch unchanged since creation" do
    @pull_request.save!

    assert @pull_request.create_merge_commit
  end

  test "successfully creates merge commit when base branch was changed since creation" do
    disable_feature_flag(:disable_xnetwork_fetch)
    @pull_request.save!

    add_commit_to_base_repository(@pull_request, @actor)

    assert @pull_request.create_merge_commit
  end

  test "successfully loads diff when base branch was changed since creation" do
    @pull_request.save!

    add_commit_to_base_repository(@pull_request, @actor)

    assert_predicate @pull_request, :diff_available?
    assert_equal 1, @pull_request.changed_files
    assert_equal ["README.md"], @pull_request.diffs.entries.map(&:path)
  end

  test "successfully creates merge commit when base branch was force-pushed" do
    Spokesd.enable_spokesd

    disable_feature_flag(:disable_xnetwork_fetch)
    @pull_request.save!

    add_commit_to_base_repository(@pull_request, @actor)
    @pull_request.synchronize!(user: @actor, repo: @repo, forced: true)

    refute_predicate @pull_request, :merged?
    refute_predicate @pull_request, :closed?

    assert @pull_request.create_merge_commit
  end

  test "successfully loads diff when base branch was force-pushed" do
    Spokesd.enable_spokesd

    @pull_request.save!

    add_commit_to_base_repository(@pull_request, @actor)
    @pull_request.synchronize!(user: @actor, repo: @repo, forced: true)

    refute_predicate @pull_request, :merged?
    refute_predicate @pull_request, :closed?

    assert_predicate @pull_request, :diff_available?
    assert_equal 1, @pull_request.changed_files
    assert_equal ["README.md"], @pull_request.diffs.entries.map(&:path)
  end

  def add_commit_to_base_repository(pull_request, actor)
    assert_changes -> { pull_request.mergeable_base_sha } do
      only = [RepositorySyncJob]
      new_mergeable_base_commit = perform_enqueued_jobs(only: only) do
        pull_request.base_repository.heads.find("master").append_commit({
          message: "blah", committer: actor
        }, actor) do |files|
          files.add("SOME-RANDOM-FILE.md", "foobar")
        end
      end

      pull_request.reload

      refute_predicate pull_request, :merged?
      refute_predicate pull_request, :closed?
      assert_equal new_mergeable_base_commit.oid, pull_request.mergeable_base_sha
    end
  end
end
