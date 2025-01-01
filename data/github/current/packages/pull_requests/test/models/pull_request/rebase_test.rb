# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestRebaseTest < GitHub::TestCase
  include HydroTestHelpers
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @owner = create(:user)
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: @forker, repository: @source)
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

    @pull.create_merge_commit unless GitHub.flipper[:pull_request_generate_rebase_sync].enabled?

    WebFlowHelper.setup_webflow
  end

  def ensure_pull_has_merge_conflict
    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      @source.refs.find("master").append_commit({
        message: "Commit on master",
        committer: @owner,
      }, @owner) do |files|
        files.add("README.md", "Will this conflict?")
      end

      @fork.refs.find("topic").append_commit({
        message: "Commit on topic",
        committer: @forker,
      }, @forker) do |files|
        files.add("README.md", "This will conflict")
      end
    end

    @pull.reload
  end

  test "brings head branch ahead of base branch" do
    @pull.create_merge_commit

    assert_predicate @pull, :behind_base?
    assert_predicate @pull, :mergeable?

    assert old_head_sha = @pull.head_sha

    with_enqueued_pr_sync_jobs do
      PullRequest::Rebase.new(pull: @pull, actor: @forker).rebase
    end
    @pull.reload

    refute_predicate @pull, :behind_base?
    assert_equal :unknown, @pull.merge_state.status
    refute_equal old_head_sha, @pull.head_sha
  end

  test "raises an exception without head repository permissions" do
    refute_operator @fork, :pushable_by?, @owner

    assert_raises PullRequest::PermissionError do
      PullRequest::Rebase.new(pull: @pull, actor: @owner).rebase
    end
  end

  test "raises an exception on conflict" do
    ensure_pull_has_merge_conflict

    refute_predicate @pull, :mergeable?

    assert_raises PullRequest::RebaseConflictError do
      PullRequest::Rebase.new(pull: @pull, actor: @forker).rebase
    end
  end

  test "raises an exception on expected head ref difference" do
    expected_head_oid = @source.commits.find(@pull.head_sha).first_parent_oid

    assert_raises PullRequest::RefMismatch do
      PullRequest::Rebase.new(pull: @pull, actor: @forker, expected_head_oid: expected_head_oid).rebase
    end
  end

  test "raises an exception when head ref doesn't exist" do
    head_ref = @pull.head_repository.heads.find(@pull.head_ref)
    head_ref.delete(@pull.user)

    assert_raises PullRequest::HeadMissing do
      PullRequest::Rebase.new(pull: @pull, actor: @forker).rebase
    end
  end

  test "uses the actor for the committer information" do
    rebase_commit_sha = PullRequest::Rebase.new(pull: @pull, actor: @forker).rebase
    rebase_commit = @fork.commits.find(rebase_commit_sha)

    assert_equal rebase_commit.committer_name, @forker.git_author_name
    assert_equal rebase_commit.committer_email, @forker.git_author_email

    assert_equal 1, rebase_commit.parent_count
    parent_commit = @fork.commits.find(rebase_commit.first_parent_oid)

    assert_equal parent_commit.committer_name, @forker.git_author_name
    assert_equal parent_commit.committer_email, @forker.git_author_email
  end

  test "emits a hydro event" do
    before = @pull.head_sha
    after = PullRequest::Rebase.new(pull: @pull, actor: @forker).rebase
    expected_hydro_message = {
      actor: Hydro::EntitySerializer.user(@forker),
      pull_request: Hydro::EntitySerializer.pull_request(@pull),
      repository: Hydro::EntitySerializer.repository(@pull.repository),
      category: "update_branch",
      action: "performed",
      data: {
        before: before,
        after: after,
        update_method: "rebase",
      }
    }
    assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestUserAction")
  end
end
