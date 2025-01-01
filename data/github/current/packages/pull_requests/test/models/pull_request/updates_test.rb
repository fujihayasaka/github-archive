# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestUpdatesTest < GitHub::TestCase
  include HydroTestHelpers
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @owner = create(:user, login: "ari")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "bwalsh")
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

    @pull.create_merge_commit

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
    assert_predicate @pull, :behind_base?
    assert_predicate @pull, :mergeable?

    assert old_head_sha = @pull.head_sha

    assert_predicate @pull.updateability.check_mergeability(@forker), :success?

    with_enqueued_pr_sync_jobs do
      PullRequest::Update.new(pull: @pull, actor: @forker).merge
    end
    @pull.reload

    refute_predicate @pull, :behind_base?
    assert_equal :unknown, @pull.merge_state.status
    refute_equal old_head_sha, @pull.head_sha
  end

  test "sends a single push event" do
    assert_predicate @pull, :behind_base?
    assert_predicate @pull, :mergeable?
    assert old_head_sha = @pull.head_sha

    assert_predicate @pull.updateability.check_mergeability(@forker), :success?

    Timecop.freeze do
      new_head_sha = PullRequest::Update.new(pull: @pull, actor: @forker).merge


      with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
        assert_hydro_published_partial({
          path: @fork.shard_path,
          pusher: @forker.login,
          ref_updates: [{ ref: "refs/heads/topic", before: old_head_sha, after: new_head_sha }],
          pushed_at: Time.current,
        }, schema: "github.repositories.v1.Pushed")
      end
    end
  end

  test "raises an exception without head repository permissions" do
    refute_operator @fork, :pushable_by?, @owner

    assert_raises PullRequest::PermissionError do
      PullRequest::Update.new(pull: @pull, actor: @owner).merge
    end
  end

  test "raises an exception on merge conflict" do
    ensure_pull_has_merge_conflict

    refute_predicate @pull, :mergeable?

    assert_raises PullRequest::MergeConflictError do
      PullRequest::Update.new(pull: @pull, actor: @forker).merge
    end
  end

  test "allows resolving conflicts" do
    ensure_pull_has_merge_conflict

    refute_predicate @pull, :mergeable?

    merge_commit_sha = PullRequest::Update.new(pull: @pull, actor: @forker).merge(
      base_oid: @pull.mergeable_base_sha,
      conflict_resolutions: { "README.md" => "This resolves the conflict." }
    )

    merge_commit = @fork.commits.find(merge_commit_sha)

    tree_entry = @fork.rpc.read_tree_entry(merge_commit.tree_oid, "README.md")
    assert_equal "This resolves the conflict.", tree_entry["data"]
  end

  test "raises an exception if the merge conflict was not fully resolved" do
    ensure_pull_has_merge_conflict

    refute_predicate @pull, :mergeable?

    assert_raises PullRequest::MergeConflictError do
      PullRequest::Update.new(pull: @pull, actor: @forker).merge(
        base_oid: @pull.mergeable_base_sha,
        conflict_resolutions: { "LICENSE.md" => "This does not resolve the conflict." }
      )
    end
  end

  test "raises an exception on expected head ref difference" do
    expected_head_oid = @source.commits.find(@pull.head_sha).parent_oids[0]

    assert_raises PullRequest::RefMismatch do
      PullRequest::Update.new(pull: @pull, actor: @forker, expected_head_oid: expected_head_oid).merge
    end
  end

  test "raises an exception when head ref doesn't exist" do
    head_ref = @pull.head_repository.heads.find(@pull.head_ref)
    head_ref.delete(@pull.user)

    assert_raises PullRequest::HeadMissing do
      PullRequest::Update.new(pull: @pull, actor: @forker).merge
    end
  end

  test "uses GitHub for the committer information" do
    merge_commit_sha = PullRequest::Update.new(pull: @pull, actor: @forker).merge
    merge_commit = @fork.commits.find(merge_commit_sha)

    assert_equal merge_commit.committer_name, GitHub.web_committer_name
    assert_equal merge_commit.committer_email, GitHub.web_committer_email
  end

  test "uses the actor for the author information" do
    merge_commit_sha = PullRequest::Update.new(pull: @pull, actor: @forker).merge
    merge_commit = @fork.commits.find(merge_commit_sha)

    assert_equal merge_commit.author_name, @forker.git_author_name
    assert_equal merge_commit.author_email, @forker.git_author_email
  end

  context "commit signing" do
    test "signs commit" do
      @source.update!(public: false)
      @pull.base_repository.reload

      merge_commit_sha = PullRequest::Update.new(pull: @pull, actor: @forker).merge
      merge_commit = @fork.commits.find(merge_commit_sha)

      assert_predicate merge_commit, :verified_signature?
      refute_predicate @pull.reload, :behind_base?
    end

    test "commit signing error handling" do
      GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)
      @source.update!(public: false)
      @pull.base_repository.reload

      merge_commit_sha = PullRequest::Update.new(pull: @pull, actor: @forker).merge
      merge_commit = @fork.commits.find(merge_commit_sha)

      refute_predicate merge_commit, :has_signature?
      refute_predicate @pull.reload, :behind_base?
    end
  end if GitHub.web_commit_signing_enabled?

  context "commit DCO sign off" do
    # Regression test for https://github.com/github/repos/issues/2206
    test "applies conflict merge commit with DCO sign-off for fork to source PR" do
      @source.enable_dco_signoff(actor: @owner)
      @fork.reset_dco_signoff(actor: @forker)

      ensure_pull_has_merge_conflict

      refute_predicate @pull, :mergeable?

      merge_commit_sha = PullRequest::Update.new(pull: @pull, actor: @forker).merge(
        base_oid: @pull.mergeable_base_sha,
        conflict_resolutions: { "README.md" => "This resolves the conflict." }
      )

      merge_commit = @fork.commits.find(merge_commit_sha)

      tree_entry = @fork.rpc.read_tree_entry(merge_commit.tree_oid, "README.md")
      assert_equal "This resolves the conflict.", tree_entry["data"]

      assert_equal @forker.name, merge_commit.author_name
      assert_equal @forker.git_author_email, merge_commit.author_email

      message = "Merge branch 'master' into topic"
      message += "\n\nSigned-off-by: #{@forker.name} <#{@forker.git_author_email}>"
      assert_equal message, merge_commit.message

      assert_equal GitHub.web_committer_name, merge_commit.committer_name
    end
  end

  test "emits a hydro event" do
    before = @pull.head_sha
    after = PullRequest::Update.new(pull: @pull, actor: @forker).merge
    expected_hydro_message = {
      actor: Hydro::EntitySerializer.user(@forker),
      pull_request: Hydro::EntitySerializer.pull_request(@pull),
      repository: Hydro::EntitySerializer.repository(@pull.repository),
      category: "update_branch",
      action: "performed",
      data: {
        before: before,
        after: after,
        update_method: "merge_commit",
      }
    }
    assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestUserAction")
  end
end
