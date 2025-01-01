# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestOverTimeTest < GitHub::TestCase

  EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
  MISSING_COMMIT = "0000000000000000000000000000000000000000"

  self.these_tests_are_order_dependent_and_yearn_to_be_random

  include GitHub::DatabaseQueryWarningsTestHelpers
  include PullRequestSynchronizationTestHelpers
  include HydroTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @owner = create(:user, login: "owner")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "forker")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)
    @issue = create(:issue, user: @forker, repository: @source)

    @pull = PullRequest.create_for!(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)

    example_repo_snapshot
  end

  setup do
    reset_cache
    example_repo_restore
  end

  test "calculating the initial base sha" do
    assert_equal @source.ref_to_sha("master"), @pull.base_sha
    assert_equal @pull.base_sha, @pull.historical_comparison.base_sha
  end

  test "recalculating the base sha when the base ref moves" do
    original_base_sha = @pull.base_sha

    commit = @source.heads.find("master-forward-2").target

    @source.heads.find("master").update(commit, @source.owner)

    assert_equal @source.ref_to_sha("master-forward-2"),
                 @source.ref_to_sha("master")

    @pull.reload

    assert_equal original_base_sha, @pull.base_sha
    assert_equal @pull.base_sha, @pull.historical_comparison.base_sha
    assert_equal 3, @pull.historical_comparison.commits.length
  end

  test "recalculating the base sha when base is merged into head" do
    commit = @source.heads.find("master-forward-2").target

    @source.heads.find("master").update(commit, @source.owner)

    assert_equal @source.ref_to_sha("master-forward-2"),
                 @source.ref_to_sha("master")

    commit = @fork.heads.find("topic-merged-master-2").target

    GitHub.dogstats.expects(:distribution_timing_since).with("pullrequest.sync.time_since_head_ref_update", anything, tags: ["head_sha_changed:true"])

    with_enqueued_pr_sync_jobs do
      @fork.heads.find("topic").update(commit, @fork.owner)
    end

    assert_equal @fork.ref_to_sha("topic-merged-master-2"),
                 @fork.ref_to_sha("topic")

    @pull.reload

    assert_equal @source.ref_to_sha("master-forward-2"), @pull.base_sha
    assert_equal @pull.base_sha, @pull.historical_comparison.base_sha

    assert_equal @fork.ref_to_sha("topic-merged-master-2"), @pull.head_sha
    assert_equal @pull.head_sha, @pull.historical_comparison.head_sha
    assert_equal 4, @pull.historical_comparison.commits.length

    assert !@pull.merged?
    assert @pull.open?
  end

  test "reporting time_since_head_ref_update" do
    commit = @source.heads.find("master-forward-2").target
    @source.heads.find("master").update(commit, @source.owner)
    assert_equal @source.ref_to_sha("master-forward-2"),
                 @source.ref_to_sha("master")
    commit = @fork.heads.find("topic-merged-master-2").target

    time = Time.now
    GitHub.dogstats.expects(:distribution_timing_since).with("pullrequest.sync.time_since_head_ref_update", time, tags: ["head_sha_changed:true"])

    Timecop.freeze(time) do
      with_enqueued_pr_sync_jobs do
        @fork.heads.find("topic").update(commit, @fork.owner)
      end
    end
  end

  test "recalculating the base sha when head is merged into base" do

    with_enqueued_pr_sync_jobs do
      commit = @fork.heads.find("topic-merged-master-2").target
      @fork.heads.find("topic").update(commit, @fork.owner)

      assert_equal @fork.ref_to_sha("topic-merged-master-2"),
                   @fork.ref_to_sha("topic")

      commit = @source.heads.find("master-merged-topic").target
      @source.heads.find("master").update(commit, @source.owner)

      assert_equal @source.ref_to_sha("master-merged-topic"),
                   @source.ref_to_sha("master")
    end

    @pull.reload

    assert_equal @source.ref_to_sha("master-forward-2"), @pull.base_sha
    assert_equal @pull.base_sha, @pull.historical_comparison.base_sha

    assert_equal @fork.ref_to_sha("topic-merged-master-2"), @pull.head_sha
    assert_equal @pull.head_sha, @pull.historical_comparison.head_sha
    assert_equal 4, @pull.historical_comparison.commits.length

    assert @pull.merged?
    assert @pull.closed?

    refute_nil @pull.issue.events.merges.last

    # merge commit was inferred as the commit that merged head into base
    assert_equal @pull.determine_merge_sha, @pull.issue.events.merges.last.commit_id
    assert_equal @pull.issue.events.merges.last.commit_id, @source.heads.find("master-merged-topic").target_oid
    assert_equal @owner, @pull.issue.events.merges.last.actor
  end

  test "deletes branch when head is merged into base" do
    @fork.update_merge_settings(@fork.owner, delete_branch_allowed: true)
    @pull.repository.update_merge_settings(@owner, delete_branch_allowed: true)
    @fork.add_member @owner

    assert @fork.heads.exist?(@pull.head_ref)

    with_enqueued_pr_sync_jobs(additional_jobs: [PullRequests::CleanupHeadRefJob]) do
      commit = @fork.heads.find("topic-merged-master-2").target
      @fork.heads.find("topic").update(commit, @fork.owner)

      assert_equal @fork.ref_to_sha("topic-merged-master-2"),
                   @fork.ref_to_sha("topic")

      commit = @source.heads.find("master-merged-topic").target
      @source.heads.find("master").update(commit, @source.owner)

      assert_equal @source.ref_to_sha("master-merged-topic"),
                   @source.ref_to_sha("master")
    end

    @pull.reload

    assert @pull.merged?, "PR is merged"
    refute @pull.head_ref_exist?, "Branch should be deleted"
  end

  test "recalculating the head sha when the head ref moves" do
    original_head_sha = @pull.head_sha

    commit = @fork.heads.find("topic-merged-master-2").target

    with_enqueued_pr_sync_jobs do
      @fork.heads.find("topic").update(commit, @fork.owner)
    end

    assert_equal @fork.ref_to_sha("topic-merged-master-2"),
                 @fork.ref_to_sha("topic")

    @pull.reload

    refute_equal original_head_sha, @pull.head_sha
    assert_equal @pull.head_sha, @pull.historical_comparison.head_sha
    assert_equal 6, @pull.historical_comparison.commits.length
  end

  test "adjusting commit list when the base ref changes" do
    issue = create(:issue, user: @forker, repository: @source)
    pull = PullRequest.create_for!(@source,
      base: "master-forward-2",
      head: "#{@fork.user}:topic",
      user: issue.user,
      issue: issue)

    assert_equal 3, pull.changed_commits.length

    pull.change_base_branch(@source.owner, "topic-partial-merge")

    assert_equal 1, pull.changed_commits.length
  end

  test "creates a PullRequestEvent when the head ref moves" do
    T.unsafe(GitHub).reset_stratocaster

    commit = @fork.heads.find("topic-merged-master-2").target

    with_enqueued_pr_sync_jobs(additional_jobs: [ProcessEventJob]) do
      @fork.heads.find("topic").update(commit, @fork.owner)
    end

    event = GitHub.stratocaster_store.all.detect { |e| e.event_type == "PullRequestEvent" }
    assert event, "expected a PullRequestEvent"
    assert_equal @pull.id, event.payload["pull_request"]["id"]
    assert_equal :synchronize, event.payload["action"]
  end

  test "instruments a pull_request.synchronize event when the head ref moves" do
    events = subscribe "pull_request.synchronize"
    # Keep track of the current head SHA, as that will be our "before" after
    # head moves.
    previous_head_sha = @pull.head_sha

    commit = @fork.heads.find("topic-merged-master-2").target

    with_enqueued_pr_sync_jobs do
      @fork.heads.find("topic").update(commit, @fork.owner)
    end
    @pull.reload
    expected_payload = {
      pull_request_id: @pull.id,
      pull_request_url: @pull.permalink,
      pull_request_title: @pull.title,
      issue_id: @issue.id,
      actor: @forker.login,
      actor_id: @forker.id,
      before: previous_head_sha,
      after: @pull.head_sha,
      spammy: false,
      allowed: false,
      approved_before: nil,
      approved_after: nil,
      repo: @source.nwo,
      repo_id: @source.id,
      public_repo: @source.public?,
      user: @forker.login,
      user_id: @forker.id,
    }

    assert event = events.pop, "expected an instrumentation event"
    assert_subset_hash expected_payload, event.payload
  end

  if GitHub.spamminess_check_enabled?
    test "does not instrument a pull_request.synchronize event if the pull request is spammy" do
      @pull.user.update_attribute(:spammy, true)

      events = subscribe "pull_request.synchronize"

      commit = @fork.heads.find("topic-merged-master-2").target

      with_enqueued_pr_sync_jobs do
        @fork.heads.find("topic").update(commit, @owner)
      end
      @pull.reload

      refute events.pop, "expected no instrumentation events"
    end

    test "instruments a pull_request.synchronize event for a spammy user acting on own repo" do
      pull_author = create(:user)
      @pull.user = pull_author
      @pull.user.save
      @pull.repository.owner = pull_author
      @pull.repository.save
      pull_author.update_attribute(:spammy, true)

      events = subscribe "pull_request.synchronize"

      commit = @fork.heads.find("topic-merged-master-2").target

      with_enqueued_pr_sync_jobs do
        @fork.heads.find("topic").update(commit, @fork.owner)
      end
      @pull.reload

      assert event = events.pop, "expected an instrumentation event"
    end
  end

  test "recalculating base sha when the head is rebased onto base" do
    original_head_sha = @pull.head_sha

    commit = @source.heads.find("master-forward-2").target

    @source.heads.find("master").update(commit, @source.owner)

    assert_equal @source.ref_to_sha("master-forward-2"),
                 @source.ref_to_sha("master")

    commit = @fork.heads.find("topic-rebased-on-master").target

    with_enqueued_pr_sync_jobs do
      @fork.heads.find("topic").update(commit, @fork.owner)
    end

    assert_equal @fork.ref_to_sha("topic-rebased-on-master"),
                 @fork.ref_to_sha("topic")

    @pull.reload

    refute_equal original_head_sha, @pull.head_sha
    assert_equal @pull.head_sha, @pull.historical_comparison.head_sha
    assert_equal 2, @pull.historical_comparison.commits.length

    assert_equal @source.ref_to_sha("master"), @pull.base_sha
  end

  test "reopening a closed pull request with new commits" do
    original_head_sha = @pull.head_sha
    assert @pull.save

    @pull.close(@owner)
    assert @pull.closed?

    # update topic to be two commits ahead plus merging master
    commit = @fork.heads.find("topic-merged-master-2").target
    @fork.heads.find("topic").update(commit, @fork.owner, post_receive: false)
    @fork.update_attribute :pushed_at, @fork.pushed_at + 1
    assert_equal @fork.ref_to_sha("topic-merged-master-2"),
                 @fork.ref_to_sha("topic")

    pull = PullRequest.first!
    assert pull.open(@owner)
    assert pull.open?
    assert !pull.closed?
    assert_nil pull.closed_at

    refute_equal original_head_sha, pull.head_sha
    assert_equal pull.head_sha, pull.historical_comparison.head_sha
    assert_equal 6, pull.historical_comparison.commits.length
  end

  test "finding open pull requests based on a ref in a certain repository" do
    results = PullRequest.find_open_based_on_ref(@source, "refs/heads/master")
    assert_includes results, @pull
    results = PullRequest.find_open_based_on_ref(@source, "master")
    assert_includes results, @pull
  end

  test "finding open pull requests generates no query warning" do
    assert_no_query_warnings do
      results = PullRequest.find_open_based_on_ref(@source, "refs/heads/🇫🇷")
      assert_empty results
    end
  end

  test "finding open pull request ids based on a ref sorts by id desc" do
    other_pull = PullRequest.create_for!(
      @source,
      title: "hello",
      user: @owner,
      base: "master",
      head: "master-forward-2",
    )
    results = PullRequest.find_open_ids_based_on_ref(@source, "master")
    assert_equal [@pull, other_pull].map(&:id).sort.reverse, results
  end

  test "finding other open pulls based on head ref generates no query warning" do
    ref_name = "#{GRIN_EMOJI}"
    ref = @fork.heads.create(ref_name, @fork.heads.find("master").target, @fork.owner)
    metadata = { message: "blah", committer: @fork.owner }
    ref.append_commit(metadata, @fork.owner)

    pull = PullRequest.create_for!(@fork,
              base: "master",
              head: ref_name,
              user: @fork.owner,
              title: "blah",
              body: "blah")
    pull.close

    assert_no_query_warnings do
      refute pull.other_open_pulls_using_head_ref?
    end
  end

  test "updating a pull request's diffstat after a push" do
    metadata = { message: "first diffstat commit", committer: @source.owner }
    parent   = @source.ref_to_sha("master")

    # Create the "diffstat" branch with one commit. It's a two-line file, so we
    # should have two additions and no deletions.
    commit = @source.commits.create(metadata, parent) do |files|
      files.add("diffstat_test_1", "two\nlines\n")
    end
    ref    = @source.heads.create("diffstat", commit, @source.owner, post_receive: false)

    # Create a new pull request for the diffstat branch
    pull = create(:pull_request,
      repository: @source,
      base_repository: @source,
      base_user: @source.owner,
      base_ref: "master",
      head_repository: @source,
      head_user: @source.owner,
      head_ref: ref.name,
      issue: @issue,
    )

    assert_equal 1, pull.total_commits
    assert_equal 2, pull.additions
    assert_equal 0, pull.deletions
    assert_equal 1, pull.changed_files

    # Add another commit to the "diffstat" branch that deletes a line from
    # "diffstat_test_1" (which should lower the additions from 2 to 1) and adds
    # another file with 3 lines (which should raise the additions from 1 to 4).
    # It also deletes file1, which is a 3 line file, so there should be 3
    # deletions afterwards.
    metadata[:message] = "second diffstat commit"
    commit = @source.commits.create(metadata, commit.oid) do |files|
      files.add("diffstat_test_1", "two\n")
      files.add("diffstat_test_2", "first\nsecond\nthird")
      files.remove("file1")
    end
    with_enqueued_pr_sync_jobs do
      ref.update(commit.oid, @source.owner)
    end

    pull = PullRequest.find(pull.id)

    assert_equal 2, pull.total_commits
    assert_equal 4, pull.additions
    assert_equal 3, pull.deletions
    assert_equal 3, pull.changed_files
  end

  test "detecting when a pull request is merged" do
    commit = @source.heads.find("master-merged-topic").target
    @source.heads.find("master").update(commit, @source.owner, post_receive: false)
    @source.update_attribute :pushed_at, @source.pushed_at + 1

    commit = @fork.heads.find("topic-merged-master-2").target
    @fork.heads.find("topic").update(commit, @fork.owner, post_receive: false)
    @fork.update_attribute :pushed_at, @fork.pushed_at + 1

    perform_enqueued_jobs(only: SynchronizePullRequestJob) do
      PullRequest.synchronize_requests_for_ref(@source, "refs/heads/master", @owner)
    end

    assert_equal 1, PullRequest.count
    pull = PullRequest.first!

    assert_equal @source.ref_to_sha("master-forward-2"), pull.base_sha
    assert_equal pull.base_sha, pull.historical_comparison.base_sha

    assert_equal @fork.ref_to_sha("topic-merged-master-2"), pull.head_sha
    assert_equal pull.head_sha, pull.historical_comparison.head_sha
    assert_equal 4, pull.historical_comparison.commits.length

    assert pull.merged?
    assert pull.closed?
    assert_equal @owner, pull.merged_by
  end

  # this is calling synchronize_requests_for_ref directly to simulate both ref updates
  # being pushed at the same time. it would be nice to have a better pattern for this.
  test "detecting when a pull request is merged, after the head ref is deleted" do
    commit = @source.heads.find("master-merged-topic").target

    @source.heads.find("master").update(commit, @source.owner, post_receive: false)
    @source.update_attribute :pushed_at, @source.pushed_at + 1

    @fork.heads.find("topic").delete(@fork.owner, post_receive: false)
    @fork.update_attribute :pushed_at, @fork.pushed_at + 1

    perform_enqueued_jobs(only: SynchronizePullRequestJob) do
      PullRequest.synchronize_requests_for_ref(@source, "refs/heads/master", @owner)
    end

    @pull.reload

    assert_equal @pull.head_sha, @pull.historical_comparison.head_sha
    assert_equal 3, @pull.historical_comparison.commits.length

    assert @pull.merged?
    assert @pull.closed?
    assert_equal @owner, @pull.merged_by
  end

  test "detecting when a pull request is closed, when a cross-repo pull force-pushes the value of the base ref to the head ref" do
    commit = @source.heads.find("master").target

    with_enqueued_pr_sync_jobs do
      @fork.heads.find("topic").update(commit, @fork.owner)
    end

    @pull.reload

    assert @pull.closed?, "pull request should be closed"
    assert !@pull.merged?, "pull request should not be merged"
    refute @pull.corrupt?, "pull request should not be corrupt"
    assert_equal "There are no new commits on the #{@fork.owner}:topic branch.", @pull.not_reopenable_reason
  end

  test "detecting when a pull request is closed, when a same-repo pull force-pushes the value of the base ref to the head ref" do
    @pull = PullRequest.create_for!(@source,
      base: "master",
      head: "master-forward-2",
      user: @source.owner,
      title: "le pr",
      body: "yup",
    )

    commit = @source.heads.find("master").target

    with_enqueued_pr_sync_jobs do
      @source.heads.find("master-forward-2").update(commit, @source.owner)
    end

    @pull.reload

    assert @pull.closed?, "pull request should be closed"
    assert !@pull.merged?, "pull request should not be merged"
    refute @pull.corrupt?, "pull request should not be corrupt"
    assert_equal "There are no new commits on the master-forward-2 branch.", @pull.not_reopenable_reason
  end

  test "a corrupt PR (missing the specified commits)" do
    refute_predicate @pull, :corrupt?

    @pull.update!(head_sha: "deadbeef" * 5)
    @pull.reload

    assert_predicate @pull, :corrupt?
  end

  test "an unavailable diff when the head commit is in the commits cache but not in the base repo and the head repo is deleted" do
    assert @pull.cross_repo?
    assert @pull.base_repository.public?

    enable_cache_storage

    # Don't run MaintainTrackingRef
    commit = with_enqueued_pr_sync_jobs do
      metadata = { message: "blah", committer: @fork.owner }
      @fork.heads.find("topic").append_commit(metadata, @fork.owner) {}
    end

    @pull.reload
    assert_equal @pull.head_sha, commit.oid

    diffs = @pull.historical_comparison.diffs

    key = @pull.repository.rpc.diff_toc_cache_key(diffs.sha1, diffs.sha2, diffs.base_sha)
    GitHub.cache.delete(key)
    GitHub.cache.delete(diffs.entries_hash_cache_key)

    # commit should not be in the base repo
    refute @pull.base_repository.rpc.object_exists?(commit.oid, "commit")

    # but it should be in the cache
    assert @pull.base_repository.rpc.cache.get(commit.gitrpc_cache_key)

    @fork.remove_from_disk
    @fork.destroy

    # lookup a new PullRequest instance to make sure all memoized ivars are
    # reset, forcing a hit to GitRPC now that the repo doesn't exist on disk
    @pull = PullRequest.find(@pull.id)

    assert_nil @pull.head_repository
    refute @pull.corrupt?, "expected diff to not be corrupt"
    refute @pull.diff_available?, "expected diff to not be available"
    assert @pull.diffs.missing_commits?, "expected diff to be missing commits"

    reset_cache
    disable_cache_storage
  end

  # If a deploy key is used to push, and the account that verified the key no
  # longer exists, there will be no pusher to reference. Currently we don't
  # flag the PR as merged because there's no actor for the event.
  #
  # This is calling synchronize_requests_for_ref directly so we can pass a nil user.
  # The ref update methods currently require a user.
  test "does not make a PR merged after a verifier-less deploy key push" do
    commit = @source.heads.find("master-merged-topic").target

    @source.heads.find("master").update(commit, @source.owner, post_receive: false)
    @source.update_attribute :pushed_at, @source.pushed_at + 1

    PullRequest.synchronize_requests_for_ref(@source, "refs/heads/master", nil)

    @pull.reload

    assert_equal @pull.head_sha, @pull.historical_comparison.head_sha
    assert_equal 3, @pull.historical_comparison.commits.length

    refute @pull.merged?
  end

  test "detecting when a pull request is merged, when the merge commit message also 'closes' it" do
    assert(commit_oid = @pull.create_merge_commit)

    ref = @pull.base_repository.heads.find(@pull.base_ref)

    with_enqueued_pr_sync_jobs do
      ref.merge(@source.owner,
                commit_oid,
                commit_message: "Closes ##{@pull.number}")
    end

    @pull.reload

    assert @pull.merged?
  end

  context "#async_pull_comparison" do
    test "returns a new comparison" do
      comparison = @pull.async_pull_comparison.sync

      assert_equal @pull.merge_base, comparison.base_commit.oid
      assert_equal @pull.merge_base, comparison.start_commit.oid
      assert_equal @pull.head_sha, comparison.end_commit.oid
    end

    test "returns `nil` if `base_commit_oid` is not a valid commit oid" do
      assert_nil @pull.async_pull_comparison(base_oid: "invalid").sync
    end

    test "returns `nil` if `start_commit_oid` is not a valid commit oid" do
      assert_nil @pull.async_pull_comparison(start_oid: "invalid").sync
    end

    test "returns `nil` if `end_commit_oid` is not a valid commit oid" do
      assert_nil @pull.async_pull_comparison(end_oid: "invalid").sync
    end

    test "returns `nil` if `base_commit_oid` can't be found" do
      assert_nil @pull.async_pull_comparison(base_oid: MISSING_COMMIT).sync
    end

    test "returns `nil` if `start_commit_oid` can't be found" do
      assert_nil @pull.async_pull_comparison(start_oid: MISSING_COMMIT).sync
    end

    test "returns `nil` if `end_commit_oid` can't be found" do
      assert_nil @pull.async_pull_comparison(end_oid: MISSING_COMMIT).sync
    end

    test "returns `nil` if `base_commit_oid` refers to a non-commit object" do
      assert_nil @pull.async_pull_comparison(base_oid: EMPTY_TREE).sync
    end

    test "returns `nil` if `start_commit_oid` refers to a non-commit object" do
      assert_nil @pull.async_pull_comparison(start_oid: EMPTY_TREE).sync
    end

    test "returns `nil` if `end_commit_oid` refers to a non-commit object" do
      assert_nil @pull.async_pull_comparison(end_oid: EMPTY_TREE).sync
    end
  end

  test "detecting when a pull request's branch is deleted and closing" do
    PullRequest.after_branch_delete(@source, "refs/heads/master", @source.owner, @source.heads.find("master").target_oid)
    @pull.reload
    assert @pull.closed?
  end

  test "can update tracking ref even if the user who created the PR is gone" do
    User.create_ghost
    # The author being deleted can"t be the repo owner
    # or the postrx job won"t even be able to find the repo.
    #
    # Make a random user and set them up as the PR creator.
    creator = create(:user)
    @pull.update!(user: creator)
    @pull.issue.update!(user: creator)
    creator.destroy

    head_ref = @pull.head_repository.heads.find(@pull.head_ref)

    latest_commit = with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      committer = @pull.repository.owner
      metadata = { message: "blah", committer: committer }

      head_ref.append_commit(metadata, committer) do |files|
        files.add("blah.txt", "blahblah")
      end
    end

    assert_equal latest_commit.oid,
                 @pull.base_repository.refs.read("refs/pull/#{@pull.number}/head").target_oid
  end

  context "force push events" do
    test "force-pushing the base of a same-repo pull" do
      @pull = PullRequest.create_for!(@fork,
                base: "master",
                head: "topic",
                user: @fork.owner,
                title: "blah",
                body: "blah")

      base_repository = @pull.base_repository
      base_ref = base_repository.heads.find(@pull.base_ref)
      before_commit = base_ref.target

      metadata = { message: "force push commit", committer: base_repository.owner }
      after_commit = base_repository.commits.create(metadata, before_commit.parent_oids.first) {}

      with_enqueued_pr_sync_jobs do
        base_ref.update(after_commit, base_repository.owner)
      end

      event = @pull.events.force_pushes.first

      assert_equal "base_ref_force_pushed", event.event
      assert_nil   event.commit_id # we don't use this
      assert_equal before_commit.oid, event.before_commit_oid
      assert_equal after_commit.oid, event.after_commit_oid
      assert_equal base_repository, event.commit_repository
      assert_equal base_repository.owner, event.actor
    end

    test "force-pushing the head of a same-repo pull" do
      @pull = PullRequest.create_for!(@fork,
                base: "master",
                head: "topic",
                user: @fork.owner,
                title: "blah",
                body: "blah")

      head_repository = @pull.head_repository
      head_ref = head_repository.heads.find(@pull.head_ref)
      before_commit = head_ref.target

      metadata = { message: "force push commit", committer: head_repository.owner }
      after_commit = head_repository.commits.create(metadata, before_commit.parent_oids.first) {}

      with_enqueued_pr_sync_jobs do
        head_ref.update(after_commit, head_repository.owner)
      end

      event = @pull.events.force_pushes.first

      assert_equal "head_ref_force_pushed", event.event
      assert_nil   event.commit_id # we don't use this
      assert_equal before_commit.oid, event.before_commit_oid
      assert_equal after_commit.oid, event.after_commit_oid
      assert_equal head_repository, event.commit_repository
      assert_equal head_repository.owner, event.actor
    end

    test "force-pushing the base of a cross-repo pull" do
      base_repository = @pull.base_repository
      base_ref = base_repository.heads.find(@pull.base_ref)
      before_commit = base_ref.target

      metadata = { message: "force push commit", committer: base_repository.owner }
      after_commit = base_repository.commits.create(metadata, before_commit.parent_oids.first) {}

      with_enqueued_pr_sync_jobs do
        base_ref.update(after_commit, base_repository.owner)
      end

      event = @pull.events.force_pushes.first

      assert_equal "base_ref_force_pushed", event.event
      assert_nil   event.commit_id # we don't use this
      assert_equal before_commit.oid, event.before_commit_oid
      assert_equal after_commit.oid, event.after_commit_oid
      assert_equal base_repository, event.commit_repository
      assert_equal base_repository.owner, event.actor
    end

    test "force-pushing the head of a cross-repo pull" do
      head_repository = @pull.head_repository
      head_ref = head_repository.heads.find(@pull.head_ref)
      before_commit = head_ref.target

      metadata = { message: "force push commit", committer: head_repository.owner }
      after_commit = head_repository.commits.create(metadata, before_commit.parent_oids.first) {}

      with_enqueued_pr_sync_jobs do
        head_ref.update(after_commit, head_repository.owner)
      end

      event = @pull.events.force_pushes.first

      assert_equal "head_ref_force_pushed", event.event
      assert_nil   event.commit_id # we don't use this
      assert_equal before_commit.oid, event.before_commit_oid
      assert_equal after_commit.oid, event.after_commit_oid
      assert_equal head_repository, event.commit_repository
      assert_equal head_repository.owner, event.actor
    end

    test "force-pushing the base in a manner that does not change the branch base" do
      @pull = PullRequest.create_for!(@fork,
                base: "master",
                head: "topic",
                user: @fork.owner,
                title: "blah",
                body: "blah")

      base_repository = @pull.base_repository
      base_ref = base_repository.heads.find(@pull.base_ref)
      old_base = base_ref.target

      metadata = { message: "regular push commit", committer: base_repository.owner }

      base_ref.append_commit(metadata, base_repository.owner) {}

      metadata = { message: "force push commit", committer: base_repository.owner }
      force_push_commit = base_repository.commits.create(metadata, old_base.oid) {}

      base_ref.update(force_push_commit, base_repository.owner)

      assert @pull.events.force_pushes.empty?
    end

    test "doesn't create a force push event when a PR is created before the post receive job for head branch creation runs" do
      pull = nil
      # create the ref without performing jobs, so we can run
      # the postreceive job *after* creating the PR.
      ref = @fork.heads.create("topic-2", @fork.heads.find("master").target, @fork.owner)
      metadata = { message: "blah", committer: @fork.owner }
      ref.append_commit(metadata, @fork.owner) {}

      pull = PullRequest.create_for!(@fork,
                base: "master",
                head: "topic-2",
                user: @fork.owner,
                title: "blah",
                body: "blah")

      with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) { assert_hydro_messages(count: 2, schema: "github.repositories.v1.Pushed") }

      assert_empty pull.events.force_pushes
    end
  end
end
