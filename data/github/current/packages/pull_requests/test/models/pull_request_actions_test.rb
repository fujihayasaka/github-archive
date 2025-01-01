# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestActionsTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @ryan = create(:user, email: "rtomayko@gmail.com", login: "rtomayko")
    @owner = create(:user, login: "owner")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "forker")
    @drama  = create(:user, login: "jdrama", email: "drama@example.com")
    @drama.add_email "drama@example.com"
    @turtle = create(:user, login: "turtle")
    @vince  = create(:staff_admin_user, login: "vince")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)
    @issue  =
      create(:issue,
        user: @forker,
        repository: @source,
        body: "hey @vince look at this real quick",
      )

    @commit = @fork.commits.find(@fork.ref_to_sha("topic"))
    @commit.freeze

    @comm   = create :commit_comment, user: @owner, repository: @fork,
      position: 0, path: "color.js", commit_id: @commit.oid

    @comm.freeze

    example_repo_snapshot(snapshot_spokesdb: true)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    reset_cache
    reset_monolith_redis_rate_limiter
    example_repo_restore

    @pull =
      PullRequest.new(
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @fork.owner,
        status: "open",
        )
    refute_nil @pull.issue
    @issue.pull_request = @pull
  end

  test "closing a pull request" do
    assert @pull.save
    assert_nil @pull.closed_at
    @pull.close(@owner)
    assert @pull.closed?
    assert !@pull.open?
    refute_nil @pull.closed_at
  end

  test "reopening a closed pull request" do
    assert @pull.save
    @pull.close(@owner)
    assert @pull.closed?
    @pull.open(@owner)
    assert @pull.open?
    assert !@pull.closed?
    assert_nil @pull.closed_at
  end

  test "detecting a pull request as merged after the head repository has been deleted" do
    with_enqueued_pr_sync_jobs do
      @pull.save!
      @pull.head_repository.destroy
      @source.heads.find("master").update(@pull.head_sha, @source.owner)
    end

    @pull.reload
    assert @pull.merged?
  end

  test "still calculates merge_base after head repository has been deleted" do
    @pull.save!
    @pull.head_repository.destroy
    @pull.reload

    assert_equal "8abd54838e6ecf23cdb60fd1110f3772a878c76c", @pull.async_merge_base.sync
  end

  test "recalculates base_sha when reopened after base has non-ff push" do
    assert @pull.save
    base_sha = @pull.base_sha

    @pull.close(@owner)

    assert @pull.closed?

    base_repository = @pull.base_repository
    base_ref = base_repository.heads.find(@pull.base_ref)
    before_commit = base_ref.target

    metadata = { message: "force push commit", committer: base_repository.owner }
    after_commit = base_repository.commits.create(metadata, before_commit.parent_oids.first) {}

    with_enqueued_pr_sync_jobs do
      base_ref.update(after_commit, base_repository.owner)
    end

    @pull.reload.open(@owner)
    assert @pull.open?

    refute_equal base_sha, @pull.reload.base_sha
  end

  context "#reopenable? and #async_reopenable?" do
    test "when the PR is merely closed" do
      assert @pull.save

      @pull.close(@owner)

      assert @pull.closed?
      assert @pull.reopenable?
      assert @pull.async_reopenable?.sync
      assert_nil @pull.not_reopenable_reason
    end

    test "when the PR was merged" do
      assert @pull.save

      @pull.merge

      assert @pull.merged?
      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_nil @pull.not_reopenable_reason
    end

    test "when the PR's head repository was deleted" do
      assert @pull.save
      @pull.close(@owner)
      assert @pull.closed?

      @pull.head_repository.destroy

      @pull.reload
      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_equal "The repository that submitted this pull request has been deleted.",
        @pull.not_reopenable_reason
    end

    test "when the PR's head repository is soft deleted" do
      assert @pull.save
      @pull.close(@owner)
      assert @pull.closed?

      @pull.head_repository.update!(active: nil)

      @pull.reload
      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_equal "The repository that submitted this pull request has been deleted.",
        @pull.not_reopenable_reason
    end

    test "when the PR's head ref was deleted" do
      assert @pull.save
      @pull.close(@owner)
      assert @pull.closed?

      ref = @pull.head_repository.refs.find(@pull.head_ref)
      ref.delete(@owner)

      @pull.reload
      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_equal "The #{@pull.head_ref} branch has been deleted.",
        @pull.not_reopenable_reason
    end

    test "when the PR's base ref was deleted" do
      assert @pull.save
      @pull.close(@owner)
      assert @pull.closed?

      ref = @pull.base_repository.refs.find(@pull.base_ref)
      ref.delete(@owner)

      @pull.reload
      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_equal "The #{@pull.base_ref} branch has been deleted.",
        @pull.not_reopenable_reason
    end

    test "when the PR's refs were deleted" do
      assert @pull.save
      @pull.close(@owner)
      assert @pull.closed?

      ref = @pull.base_repository.refs.find(@pull.base_ref)
      ref.delete(@owner)
      ref = @pull.head_repository.refs.find(@pull.head_ref)
      ref.delete(@owner)

      @pull.reload
      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_equal "The #{@pull.base_ref} and #{@pull.head_ref} branches have been deleted.",
        @pull.not_reopenable_reason
    end

    test "when the commits have been merged while the PR was closed" do
      assert @pull.save
      @pull.close(@owner)
      assert @pull.closed?

      assert @pull.reopenable?

      # Merge the head into the base manually.
      @pull.base_repository.heads.find(@pull.base_ref_name).merge(@owner, @pull.head_sha)

      @pull.reload

      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_equal "These commits are already merged.",
        @pull.not_reopenable_reason
    end

    test "when the PR branch's new tip doesn't have the saved head_sha as an ancestor" do
      assert @pull.save
      @pull.close(@owner)
      assert @pull.closed?

      assert @pull.reopenable?

      # change just the branch tip commit to not descend from the old tip
      repo = @pull.head_repository
      ref  = repo.heads.find(@pull.head_ref)
      parent_oid = ref.target.parent_oids.first

      metadata = { message: "new tip", committer: repo.owner }
      commit = repo.commits.create(metadata, parent_oid) {}
      ref.update(commit, repo.owner)

      @pull.reload

      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_equal "The #{@pull.head_ref} branch was force-pushed or recreated.",
        @pull.not_reopenable_reason
    end

    test "when the PR branch was force-pushed to a zero-commit comparison and then a new commit is added" do
      assert @pull.save

      # change the head branch to the same OID as the base
      repo = @pull.head_repository
      ref  = repo.heads.find(@pull.head_ref)

      with_enqueued_pr_sync_jobs do
        ref.update(@pull.base_sha, repo.owner)
      end

      @pull.reload

      assert @pull.closed?
      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_equal "There are no new commits on the #{repo.owner}:#{@pull.head_ref} branch.",
        @pull.not_reopenable_reason

      # now add a new commit, and the reason should go away
      metadata = { message: "a new start", committer: repo.owner }
      ref.append_commit(metadata, repo.owner)

      @pull.reload

      assert @pull.reopenable?
    end

    test "when the PR's head_ref is a full 40c commit OID" do
      oid = @pull.head_repository.heads.find(@pull.head_ref).target_oid
      @pull.head_ref = oid
      refute @pull.save
      refute @pull.valid?
      assert @pull.errors.has_key? :head_ref
    end

    test "when the PR's head_ref is a short sha" do
      # An example seen in prod data was a head_ref of "6945" where no such
      # branch exists, but there is a commit oid of 694595a3c93a965497978d3c448ca606032ad95d.
      # We used to allow this but it makes knowing what we have in our database and models
      # harder. This is not allowed via the web UI or API.
      oid = @pull.head_repository.heads.find(@pull.head_ref).target_oid
      sha = oid[0, 10]
      assert !@pull.head_repository.heads.exist?(sha)

      @pull.head_ref = sha
      refute @pull.save
      refute @pull.valid?
      assert @pull.errors.has_key? :head_ref
    end

    test "when another PR with the same endpoints has been created in the interim" do
      assert @pull.save
      @pull.close(@owner)

      assert @pull.closed?
      assert @pull.reopenable?

      PullRequest.create_for!(@pull.repository,
        base: @pull.base,
        head: @pull.head,
        user: @pull.user,
        title: "dsfsdfs",
        body: "dsfdsfs")

      @pull.reload

      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_equal "There is already an open pull request from forker:topic to owner:master.",
                   @pull.not_reopenable_reason
    end

    test "when the branches have no common history, the PR gets closed and cannot be reopened" do
      assert @pull.save

      metadata = { committer: @pull.head_user, message: "disjoint history" }
      commit = @pull.head_repository.commits.create(metadata) {}

      assert_difference %(GitHub.dogstats.increments("pull_request", tags: ["action:closed_no_common_ancestor"]).count), 2 do
        with_enqueued_pr_sync_jobs { @pull.head_repository.heads.find(@pull.head_ref_name).update(commit, @pull.head_user) }
      end

      @pull.reload

      assert @pull.closed?
      assert_equal "The forker:topic branch has no history in common with owner:master.",
        @pull.not_reopenable_reason
    end

    test "when the head repo has been detached from the network, the PR gets closed and cannot be reopened" do
      pull = PullRequest.create_for!(
        @fork,
        user: @source.owner,
        base: "master",
        head_repo: @source,
        head: "#{@source.user.display_login}:master-forward-2",
        title: "some changes")

      # Detatch the root repo from the network
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        @source.set_visibility(actor: @source.owner, visibility: Repository::PRIVATE_VISIBILITY)
      end
      @source.reload
      pull.reload

      # Add a commit to the head repo (root)
      with_enqueued_pr_sync_jobs do
        metadata = { committer: pull.head_user, message: "push to extracted repo" }
        pull.head_repository.heads.find(pull.head_ref_name).append_commit(metadata, pull.head_user)
      end
      pull.reload

      assert pull.closed?
      refute pull.reopenable?
    end

    test "when the head repo has been detached from the network, commits do not sync accross the network when updating the tracking ref" do
      pull = PullRequest.create_for!(
        @fork,
        user: @source.owner,
        base: "master",
        head_repo: @source,
        head: "#{@source.user.display_login}:master-forward-2",
        title: "some changes")

      # Detatch the root repo from the network
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        @source.set_visibility(actor: @source.owner, visibility: Repository::PRIVATE_VISIBILITY)
      end
      @source.reload
      pull.reload

      # Add a commit to the head repo (root)
      metadata = { committer: pull.head_user, message: "push to extracted repo" }
      commit = pull.head_repository.heads.find(pull.head_ref_name).append_commit(metadata, pull.head_user)
      pull.head_sha = commit.oid
      pull.maintain_tracking_ref(pull.user)

      # The commit should not be found in the base repo (fork)
      assert_raises(GitRPC::ObjectMissing) { pull.base_repository.commits.find(commit.oid) }
    end

    test "when the head_sha commit no longer exists" do
      assert @pull.save
      @pull.close(@owner)

      @pull.update!(head_sha: "deadbeef" * 5)

      refute @pull.reopenable?
      refute @pull.async_reopenable?.sync
      assert_equal "The repository may be missing relevant data. Please contact support for more information.", @pull.not_reopenable_reason
    end
  end

  context "reopening and errors" do
    test "adds an error when trying to open a non-reopenable PR" do
      assert @pull.save

      @pull.merge

      assert @pull.merged?
      refute @pull.issue.open(@owner)
      refute @pull.errors[:state].empty?
    end

    test "adds no error when checking if a non-reopenable PR can be reopened" do
      assert @pull.save

      @pull.merge

      assert @pull.merged?
      refute @pull.issue.reopenable_by?(@owner)
      assert @pull.errors[:state].empty?
    end
  end

  test "generating a default title from ref named topic" do
    @pull.head_ref = "topic"
    assert_equal "Topic", @pull.default_title
  end

  test "generating a default title from ref named master" do
    @pull.head_ref = "master"
    assert_nil @pull.default_title
  end

  test "generating a default title from ref named gh-pages" do
    @pull.head_repository.refs.create("refs/heads/gh-pages", @commit.oid, @forker)
    @pull.head_ref = "gh-pages"
    @pull.head_sha = @commit.oid
    assert @pull.has_required_objects?
    assert_nil @pull.default_title
  end

  test "requires a valid issue on creation" do
    options = {
      base: "owner:master",
      head: "forker:topic",
      user: @forker,
      title: "",
      body: "check it",
    }

    count = PullRequest.count

    assert_raises(ActiveRecord::RecordInvalid) do
      PullRequest.create_for!(@source, options)
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      PullRequest.create_for!(@source, options)
    end

    assert_equal count, PullRequest.count
  end

  if GitHub.spamminess_check_enabled?
    test "considered spammy if owner is spammy" do
      @pull.user = @forker
      @pull.save
      @pull.user.mark_not_spammy
      assert !@pull.spammy?

      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { @pull.user.mark_as_spammy }
      assert @pull.reload.spammy?
    end

    test "considered spammy is hidden from everyone except staff and spammer" do
      @pull.save
      @pull.user = @forker
      @pull.user.mark_not_spammy
      @staff = @vince
      @average_joe = @turtle
      @anonymous = nil

      assert !@pull.hide_from_user?(@forker)
      assert !@pull.hide_from_user?(@staff)
      assert !@pull.hide_from_user?(@anonymous)
      assert !@pull.hide_from_user?(@average_joe)

      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { @pull.user.mark_as_spammy }
      @pull.reload

      refute @pull.hide_from_user?(@forker)
      refute @pull.hide_from_user?(@staff)
      assert @pull.hide_from_user?(@anonymous)
      assert @pull.hide_from_user?(@average_joe)
    end
  end

  context ".for_branch" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @other_branch_pull_request = PullRequest.create(
        repository: @fork,
        base_repository: @fork,
        base_user: @fork.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "ahead",
        user: @fork.owner,
        issue: create(:issue, repository: @fork)
      )

      @pull_request = PullRequest.create!(
        repository: @fork,
        base_repository: @fork,
        base_user: @fork.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        user: @fork.owner,
        issue: create(:issue, repository: @fork)
      )
    end

    test "fetches all pull requests for a given branch" do
      assert_equal 2, @fork.pull_requests.count
      assert_equal [@pull_request], @fork.pull_requests.for_branch("topic")
    end
  end

  context "#suggested_change_applicable_by" do
    test "returns false if the committer only has read access" do
      committer = create(:user)
      @pull.head_repository.add_member(committer, action: :read)

      refute @pull.suggested_change_applicable_by?(committer)
    end

    test "returns true if the committer has write access" do
      committer = create(:user)
      @pull.head_repository.add_member(committer, action: :write)

      assert @pull.suggested_change_applicable_by?(committer)
    end

    test "returns true when the user has write access to the specific ref" do
      @pull.fork_collab_allowed!

      assert @pull.suggested_change_applicable_by?(@source.owner)
    end

    test "returns false when the user has write access to the specific ref but forking turned off" do
      @pull.fork_collab_denied!

      refute @pull.suggested_change_applicable_by?(@source.owner)
    end

    test "returns true when the author has write access to the specific ref" do
      @pull.fork_collab_allowed!

      assert @pull.suggested_change_applicable_by?(@forker.owner)
    end

    test "returns true when the author has write access to the specific ref but forking turned off" do
      @pull.fork_collab_denied!

      assert @pull.suggested_change_applicable_by?(@forker.owner)
    end

    test "returns false if the committer is nil" do
      @pull.update!(user: nil)

      refute @pull.suggested_change_applicable_by?(nil)
    end
  end

  context "#change_base_branch" do
    test "successfully changes base branch" do
      pull = PullRequest.create_for!(
        @source,
        title: "blah",
        body:  "blah",
        user:  @source.owner,
        base:  "master",
        head:  "master-forward-2",
      )

      new_base = "topic-partial-merge"

      pull.change_base_branch(@source.owner, new_base)

      assert_equal new_base, pull.reload.base_ref
    end

    test "raises error when base branch does not exist" do
      pull = PullRequest.create_for!(
        @source,
        title: "blah",
        body:  "blah",
        user:  @source.owner,
        base:  "master",
        head:  "master-forward-2",
      )

      assert_raises PullRequest::BaseRefNotFoundError do
        pull.change_base_branch(@source.owner, "not-real")
      end
    end

    test "raises error when base branch is a sha that is not a head" do
      pull = PullRequest.create_for!(
        @source,
        title: "blah",
        body:  "blah",
        user:  @source.owner,
        base:  "master",
        head:  "master-forward-2",
      )
      oid = "49bc45359806bb53b70aa558c0ee9371292924f8" # an arbitrary commit sha in the repo

      assert_raises PullRequest::BaseRefNotFoundError do
        pull.change_base_branch(@source.owner, oid)
      end
    end

    test "raises error when base branch is being renamed" do
      pull = PullRequest.create_for!(
        @source,
        title: "blah",
        body:  "blah",
        user:  @source.owner,
        base:  "master",
        head:  "master-forward-2",
      )
      create(:repository_branch_rename, repository: @source, old_name: "topic-partial-merge")

      assert_raises PullRequest::RefBeingRenamedError do
        pull.change_base_branch(@source.owner, "topic-partial-merge")
      end
    end

    test "raises error when PR is closed" do
      pull = PullRequest.create_for!(
        @source,
        title: "blah",
        body:  "blah",
        user:  @source.owner,
        base:  "master",
        head:  "master-forward-2",
      )
      pull.close

      assert_raises PullRequest::BaseNotChangeableError do
        pull.change_base_branch(@source.owner, "topic-partial-merge")
      end
    end

    test "raises error when PR is merged" do
      pull = PullRequest.create_for!(
        @source,
        title: "blah",
        body:  "blah",
        user:  @source.owner,
        base:  "master",
        head:  "master-forward-2",
      )
      pull.merge

      assert_raises PullRequest::BaseNotChangeableError do
        pull.change_base_branch(@source.owner, "topic-partial-merge")
      end
    end

    test "raises a BaseNotChangeableError when a DetermineCodeowners error is raised" do
      pull = PullRequest.create_for!(
        @source,
        title: "blah",
        body:  "blah",
        user:  @source.owner,
        base:  "master",
        head:  "master-forward-2",
      )

      pull.expects(:codeowners!).raises(PullRequest::DetermineCodeownersError.new(nil))

      assert_raises PullRequest::BaseNotChangeableError do
        pull.change_base_branch(@source.owner, "topic-partial-merge")
      end
    end

    test "raises InvalidBaseRefNameError when name begins with refs/heads/" do
      pull = PullRequest.create_for!(
        @source,
        title: "blah",
        body:  "blah",
        user:  @source.owner,
        base:  "master",
        head:  "master-forward-2",
      )

      new_base = "refs/heads/master"

      assert_raises PullRequest::InvalidBaseRefNameError do
        pull.change_base_branch(@source.owner, new_base)
      end
    end

    if GitHub.merge_queues_enabled?
      test "raises a LockedForMergeQueueError when PR has been added to merge queue" do
        enable_feature_flag(:merge_queue, @source)
        @source.protect_branch(@source.default_branch,
          creator: @source.owner,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )

        pull = create(:pull_request, :with_mergeable_head,
          repository: @source,
          user: @source.owner,
        )

        queue = @source.default_merge_queue
        queue.enqueue!(pull_request: pull, enqueuer: pull.user)

        assert_raises PullRequest::LockedForMergeQueueError do
          pull.change_base_branch(@source.owner, "topic-partial-merge")
        end
      end
    end
  end
end
