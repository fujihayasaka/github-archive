# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestSynchronizeDismissStaleReviewsOnPushTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers
  extend GitHub::FeatureFlagTestHelper

  fixtures do
    @owner = create(:user, login: "ari")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @reviewer1 = create(:user, login: "reviewer1")
    @source.add_member @reviewer1, action: :write
    @reviewer2 = create(:user, login: "reviewer2")
    @source.add_member @reviewer2, action: :write

    @issue = create(:issue, user: @forker, repository: @source)

    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)

    @protected_branch = create(:protected_branch,
      repository: @source,
      name: "master",
      creator: @owner,
      pull_request_reviews_enforcement_level: :everyone,
      dismiss_stale_reviews_on_push: true,
    )

    @approved_review = create(:pull_request_review, pull_request: @pull, user: @reviewer1, body: "This looks great.")
    @approved_review.approve!

    @request_changes_review = create(:pull_request_review, pull_request: @pull, user: @reviewer2, body: "Changes requested")
    @request_changes_review.request_changes!
  end

  setup do
    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    @pull.create_merge_commit

    Spokesd.enable_spokesd
  end

  def commit_changes_to_pull
    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      @fork.refs.find("topic").append_commit({
        message: "Commit on topic",
        committer: @forker,
      }, @forker) do |files|
        files.add("README.md", "This will conflict")
      end
    end

    @pull.reload
  end

  # Does what it says on the tin: Run something both with FF enabled and disabled
  def self.enable_and_disable_feature(feature, &block)
    context "#{feature} enabled" do
      block.call(-> { enable_feature_flag(feature) })
    end

    context "#{feature} disabled" do
      block.call(-> { disable_feature_flag(feature) })
    end
  end

  test "dismisses approved reviews when new changes are commited to the PR" do
    assert_predicate @approved_review, :approved?
    assert_predicate @request_changes_review, :changes_requested?

    commit_changes_to_pull

    assert_predicate @approved_review.reload, :dismissed?
    refute_predicate @request_changes_review.reload, :dismissed?
  end

  test "advances the head ref" do
    # do this here explicitly as the pull's tracking ref will have been deleted
    # by the setup process
    @pull.maintain_tracking_ref(@pull.user)

    head_ref = @pull.repository.refs.read("refs/pull/#{@pull.number}/head")
    original_commit_oid = @fork.refs.find("topic").target_oid
    assert_equal original_commit_oid, head_ref.target_oid
    assert_equal original_commit_oid, @pull.head_sha

    commit_changes_to_pull
    head_ref = @pull.repository.refs.read("refs/pull/#{@pull.number}/head")

    refute_equal @pull.head_sha, original_commit_oid
    assert_equal @pull.head_sha, head_ref.target_oid
  end

  test "records the commit that dismissed the review" do
    commit_changes_to_pull

    assert_predicate @approved_review.reload, :dismissed?
    assert dismissal_event = @pull.issue.events.last

    assert_equal "review_dismissed", dismissal_event.event
    assert_equal @pull.head_sha, dismissal_event.after_commit_oid
  end

  test "only dismisses the latest review for a given user" do
    secondary_review = create(:pull_request_review, pull_request: @pull, user: @approved_review.user, body: "I changed my mind")
    secondary_review.request_changes!

    assert_predicate @approved_review, :approved?
    commit_changes_to_pull
    refute_predicate @approved_review.reload, :dismissed?
  end

  test "doesn't dismiss reviews if not configured" do
    @protected_branch.update_attribute :dismiss_stale_reviews_on_push, false

    assert_predicate @approved_review, :approved?
    commit_changes_to_pull
    refute_predicate @approved_review.reload, :dismissed?
  end

  test "doesn't dismiss reviews if the pull request is already closed" do
    @pull.close(@owner)

    assert_predicate @approved_review, :approved?
    commit_changes_to_pull
    refute_predicate @approved_review.reload, :dismissed?
  end

  test "doesn't dismiss reviews if there are no changes" do
    assert_predicate @approved_review, :approved?

    @pull.synchronize!(user: @owner, repo: @pull.base_repository)

    refute_predicate @approved_review.reload, :dismissed?
  end

  test "doesn't dismiss reviews if new change is just empty commit" do
    previous_head = @pull.head_sha
    with_enqueued_pr_sync_jobs do
      head_ref = @pull.head_repository.refs.find(@pull.head_ref_name)
      metadata = { message: "Rerunning CI", committer: @pull.user }
      head_ref.append_commit(metadata, @pull.user) do |_files|
        # Empty commit, nothing to see here…
      end
    end

    refute_equal previous_head, @pull.reload.head_sha
    refute_predicate @approved_review.reload, :dismissed?
  end

  test "doesn't dismiss reviews if the base is merged back into the head ref" do
    previous_head = @pull.head_sha
    with_enqueued_pr_sync_jobs do
      @protected_branch.update! \
        pull_request_reviews_enforcement_level: :off
      base_ref = @pull.base_repository.refs.find(@pull.base_ref_name)
      metadata = { message: "Merge pull request #123", committer: @owner }
      base_ref.append_commit(metadata, @owner) do |files|
        files.add("README.md", "New README")
      end
      @protected_branch.update! \
        pull_request_reviews_enforcement_level: :everyone,
      dismiss_stale_reviews_on_push: true

      @pull.merge_base_into_head(user: @pull.user)
    end

    refute_equal previous_head, @pull.reload.head_sha
    refute_predicate @approved_review.reload, :dismissed?
  end

  test "dismisses reviews if empty/merge commits are followed by a commit introducing actual changes" do
    previous_head = @pull.head_sha

    with_enqueued_pr_sync_jobs do
      # Base merged into head
      @protected_branch.update! \
        pull_request_reviews_enforcement_level: :off
      base_ref = @pull.base_repository.refs.find(@pull.base_ref_name)
      metadata = { message: "Merge pull request #123", committer: @owner }
      base_ref.append_commit(metadata, @owner) do |files|
        files.add("README.md", "New README")
      end
      @protected_branch.update! \
        pull_request_reviews_enforcement_level: :everyone,
        dismiss_stale_reviews_on_push: true

      # Update PR with merge
      @pull.merge_base_into_head(user: @pull.user)

      # HEAD moved, no reviews dismissed
      refute_equal previous_head, @pull.reload.head_sha
      previous_head = @pull.reload.head_sha
      refute_predicate @approved_review.reload, :dismissed?
      refute_predicate @request_changes_review.reload, :dismissed?

      # Empty commit
      head_ref = @pull.head_repository.refs.find(@pull.head_ref_name)
      metadata = { message: "Rerunning CI", committer: @pull.user }
      head_ref.append_commit(metadata, @pull.user) do |_files|
        # Empty commit, nothing to see here…
      end

      # HEAD moved, no reviews dismissed
      refute_equal previous_head, @pull.reload.head_sha
      previous_head = @pull.reload.head_sha
      refute_predicate @approved_review.reload, :dismissed?
      refute_predicate @request_changes_review.reload, :dismissed?

      # Commit with reviewable changes
      metadata = { message: "New code", committer: @pull.user }
      head_ref.append_commit(metadata, @pull.user) do |files|
        files.add("scary.rb", "# This code needs review")
      end
    end

    # HEAD moved, approval dismissed, request for changes not dismissed
    refute_equal previous_head, @pull.reload.head_sha
    assert_predicate @approved_review.reload, :dismissed?
    refute_predicate @request_changes_review.reload, :dismissed?
  end

  test "dismisses reviews when changes are force pushed" do
    assert_predicate @approved_review, :approved?
    assert_predicate @request_changes_review, :changes_requested?

    with_enqueued_pr_sync_jobs do
      head_ref = @pull.head_repository.heads.find(@pull.head_ref)
      orig_commit = @pull.head_repository.commits.find(@pull.head_sha)
      commit_data = { message: "This was force-pushed", committer: @pull.user }
      new_commit  = @pull.head_repository.commits.create(commit_data, orig_commit.parent_oids.first) do |files|
        files.add("aquaman.txt", "this is\na bunch of new\ncontent\nand it's\ngreat\n")
      end
      head_ref.update(new_commit.oid, @pull.user)
    end

    assert_predicate @approved_review.reload, :dismissed?
    refute_predicate @request_changes_review.reload, :dismissed?
  end

  test "dismisses reviews when base is changed to a protected branch w/ stale dismissals enabled" do
    @pull.destroy # Delete existing PR for the topic branch
    pull_with_changed_base = PullRequest.create_for(@source,
      base: "topic-partial-merge",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
    approved_review = create(:pull_request_review, pull_request: pull_with_changed_base, user: @reviewer1, body: "This looks great.")
    approved_review.approve!

    pull_with_changed_base.reload

    refute_predicate approved_review.reload, :dismissed?

    pull_with_changed_base.change_base_branch(@forker, "master")

    assert_predicate approved_review.reload, :dismissed?
  end

  test "doesn't dismiss reviews when base is automatically changed to a protected branch w/ stale dismissals enabled" do
    @pull.destroy # Delete existing PR for the topic branch
    pull_with_changed_base = PullRequest.create_for(@source,
      base: "topic-partial-merge",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
    approved_review = create(:pull_request_review, pull_request: pull_with_changed_base, user: @reviewer1, body: "This looks great.")
    approved_review.approve!

    pull_with_changed_base.reload

    refute_predicate approved_review.reload, :dismissed?

    pull_with_changed_base.change_base_branch(@forker, "master", automatic: true)

    assert_predicate approved_review.reload, :dismissed?
  end

  test "dismisses reviews when base is changed to a protected branch w/ stale dismissals enabled and additional commits are added" do
    with_enqueued_pr_sync_jobs do
      @pull.destroy # Delete existing PR for the topic branch
      pull_with_changed_base = PullRequest.create_for(@source,
        base: "topic-partial-merge",
        head: "#{@fork.user}:topic",
        user: @issue.user,
        issue: @issue)

      approved_review = create(:pull_request_review, pull_request: pull_with_changed_base, user: @reviewer1, body: "This looks great.")
      approved_review.approve!

      pull_with_changed_base.reload

      refute_predicate approved_review.reload, :dismissed?

      metadata = { message: "New code", committer: @pull.user }
      head_ref = T.must(pull_with_changed_base.head_repository).refs.find(pull_with_changed_base.head_ref_name)
      head_ref.append_commit(metadata, pull_with_changed_base.user) do |files|
        files.add("scary.rb", "# This code needs review")
      end

      pull_with_changed_base.reload

      refute_predicate approved_review.reload, :dismissed?, "second refute test"

      pull_with_changed_base.change_base_branch(@forker, "master", automatic: true)

      assert_predicate approved_review.reload, :dismissed?, "third refute test"
    end
  end

  test "dismisses stale reviews when changing to unprotected base branch" do
    @pull.destroy # Delete existing PR for the topic branch
    pull_with_changed_base = PullRequest.create_for(@source,
      base: "topic-partial-merge",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
    approved_review = create(:pull_request_review, pull_request: pull_with_changed_base, user: @reviewer1, body: "This looks great.")
    approved_review.approve!

    @fork.refs.find("topic").append_commit({
      message: "Commit on topic",
      committer: @forker,
    }, @forker) do |files|
      files.add("README.md", "This will conflict")
    end
    pull_with_changed_base.reload

    refute_predicate approved_review.reload, :dismissed?

    pull_with_changed_base.change_base_branch(@forker, "master-forward-2")

    refute_predicate approved_review.reload, :dismissed?
  end

  test "issue label limit validation is skipped during synchronize" do
    Issue.stub_const(:LABEL_LIMIT, 1) do
      2.times do |i|
        label = create(:label, name: "label-#{i}", repository: @source)
        @issue.labels << label
      end

      assert @pull.synchronize!(user: @owner, repo: @source, reopened: true)
    end
  end

  include HydroTestHelpers

  test "enqueue hydro event on synchronize" do
    before_oid = @pull.head_sha
    commit_changes_to_pull
    hydro_payload = hydro_messages(schema: "github.v1.PullRequestSynchronize").first
    assert_equal [
      :actor,
      :repository,
      :base_repository,
      :pull_request,
      :issue,
      :protected_branch,
      :ref,
      :before_oid,
      :after_oid
    ], hydro_payload.keys

    assert_equal "master", hydro_payload[:protected_branch][:name]
    assert_equal @forker.id, hydro_payload[:actor][:id]
    assert_equal @pull.id, hydro_payload[:pull_request][:id]
    assert_equal @pull.issue.id, hydro_payload[:issue][:id]

    assert_equal "topic", hydro_payload[:ref]
    assert_equal hydro_payload[:before_oid], before_oid
    assert_equal hydro_payload[:after_oid], @pull.head_sha

    assert_equal @source.id, hydro_payload[:base_repository][:id]
    assert_equal @fork.id, hydro_payload[:repository][:id]
  end
end

class PullRequestSynchronizeUpdateRevisionsOnPushTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    @owner = create(:user)
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)
  end

  setup do
    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    @issue = create(:issue, user: @forker, repository: @source)
    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@forker}:topic",
      user: @forker,
      issue: @issue,
      draft: true,
    )

    @pull.create_merge_commit

    Spokesd.enable_spokesd
  end

  test "leaves PR in `draft` on changes pushed" do
    @pull.draft_state!
    assert_equal "draft", @pull.reviewable_state

    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      @fork.refs.find("topic").append_commit({
        message: "Commit on topic",
        committer: @forker,
      }, @forker) do |files|
        files.add("README.md", "Content change")
      end
    end

    @pull.reload

    assert_equal "draft", @pull.reviewable_state
  end
end

class PullRequestSynchronizeDisableAutoMergeOnPushTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner
    @merge_queue_bot = create(:merge_queue_integration)

    @owner = create(:user)
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    example_repo_snapshot
  end

  setup do
    GitHub.stubs(:merge_queue_bot).returns(@merge_queue_bot.user)

    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    @issue = create(:issue, user: @forker, repository: @source)
    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@forker}:topic",
      user: @forker,
      issue: @issue,
      draft: true,
    )
    @pull.ready_state!
    @source.protect_branch(@pull.base_ref, creator: @pull.user, required_pull_request_reviews: { require_code_owner_reviews: true }, entry_point: :test_case)
    @source.allow_auto_merge(actor: @owner)

    @pull.create_merge_commit

    Spokesd.enable_spokesd
  end

  test "disables auto-merge when pushed to by a user without write access" do
    create(:auto_merge_request, pull_request: @pull, user: @owner)
    assert @pull.auto_merge_request.present?
    refute @source.writable_by?(@forker)

    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      @fork.refs.find("topic").append_commit({
        message: "Commit on topic",
        committer: @forker,
      }, @forker) do |files|
        files.add("README.md", "Content change")
      end
    end

    refute @pull.reload.auto_merge_request.present?
  end

  test "does not disable auto-merge when pushed to by the merge queue" do
    create(:auto_merge_request, pull_request: @pull, user: @owner)
    assert @pull.auto_merge_request.present?
    refute @source.writable_by?(@forker)

    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      @fork.refs.find("topic").append_commit({
        message: "Commit on topic",
        committer: @forker,
      }, MergeQueues.system_actor) do |files|
        files.add("README.md", "Content change")
      end
    end

    assert @pull.reload.auto_merge_request.present?, "the auto merge request should still exist"
  end

  test "disables auto-merge when base is changed by a user without write access" do
    create(:auto_merge_request, pull_request: @pull, user: @owner)
    assert @pull.auto_merge_request.present?
    refute @source.writable_by?(@forker)

    @pull.change_base_branch(@forker, "🍷wine")

    refute @pull.reload.auto_merge_request.present?
  end

  test "doesn't disable auto-merge when pushed to by a user with write access" do
    create(:auto_merge_request, pull_request: @pull, user: @owner)
    assert @pull.auto_merge_request.present?
    assert @source.writable_by?(@owner)

    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      @fork.refs.find("topic").append_commit({
        message: "Commit on topic",
        committer: @owner,
      }, @owner) do |files|
        files.add("README.md", "Content change")
      end
    end

    assert @pull.reload.auto_merge_request.present?
  end

  test "doesn't disable auto-merge when base is changed by a user with write access" do
    create(:auto_merge_request, pull_request: @pull, user: @owner)
    assert @pull.auto_merge_request.present?
    assert @source.writable_by?(@owner)

    @pull.change_base_branch(@owner, "🍷wine")

    assert @pull.reload.auto_merge_request.present?
  end

  test "doesn't disable auto-merge when pushed to by dependabot" do
    create(:auto_merge_request, pull_request: @pull, user: @owner)
    assert @pull.auto_merge_request.present?

    make_trusted_oauth_apps_owner
    dependabot_app = create(:dependabot_integration)
    result = dependabot_app.install_on(
      @owner,
      repositories: @source,
      installer: @owner,
      entry_point: :test_case
    )
    dependabot = result.installation.bot

    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      @fork.refs.find("topic").append_commit({
        message: "Commit on topic",
        committer: dependabot,
      }, dependabot) do |files|
        files.add("README.md", "Content change")
      end
    end

    assert @pull.reload.auto_merge_request.present?
  end
end

class PullRequestWithSynchronizeLockTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "ari")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: forker, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: forker, repository: @source)

    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    unlock(@pull)
  end

  def lock(pull)
    name = pull.name_for_synchronize_lock
    mutex = GitHub::Redis::Mutex.new(name)
    assert mutex.try_lock
  end

  def unlock(pull)
    name = pull.name_for_synchronize_lock
    mutex = GitHub::Redis::Mutex.new(name)
    mutex.unlock!
  end

  test "logs successful lock acquisition to Datadog" do
    Spokesd.enable_spokesd

    assert_difference -> {
      GitHub.dogstats.increments("pull_request", tags: ["action:synchronize_lock_acquired"]).length
    }, 1 do
      @pull.synchronize!(user: @owner, repo: @source, lock_options: { wait: (0.1).seconds })
    end
  end

  test "logs to Datadog when lock acquisition times out" do
    Spokesd.enable_spokesd

    lock(@pull)
    assert_difference -> {
      GitHub.dogstats.increments("pull_request", tags: ["action:synchronize_lock_timed_out"]).length
    }, 1 do
      @pull.synchronize!(user: @owner, repo: @source, lock_options: { wait: (0.1).seconds })
    end
  end

  test "raises LockAquisitionError if lock cannot be acquired in strict mode" do
    lock(@pull)

    assert_raises PullRequest::SynchronizationDependency::LockAcquisitionError do
      @pull.synchronize!(
        user: @owner,
        repo: @source,
        lock_options: { strict: true, wait: (0.1).seconds }
      )
    end
  end
end

class PullRequestSynchronizeRequestsForRefTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @owner = create(:user)
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    @pulls = (1..3).map do |i|
      issue = create(:issue, user: @forker, repository: @source)
      ref = @fork.heads.create("topic-#{i}", @fork.heads.find("master").target, @forker)
      ref.append_commit({ message: "chore: add boilerplate", committer: @forker }, @forker) do |files|
        files.add("addition-#{i}.txt", "contents")
      end
      PullRequest.create_for(@source,
                             base: "master",
                             head: "#{@fork.user}:topic-#{i}",
                             user: @forker,
                             issue: issue)
    end

    Spokesd.enable_spokesd
  end

  test "passing `:excluded_pull_ids` skips over the specified PRs" do
    Spokesd.enable_spokesd

    @pulls.each { |pr| pr.update_attribute(:mergeable, true) }

    perform_enqueued_jobs(only: [PullRequestSynchronizationJob, SynchronizePullRequestJob]) do
      PullRequest.synchronize_requests_for_ref(@source, "master", @owner, excluded_pull_ids: [@pulls[1].id])
    end

    # `synchronize!` clears `mergeable` on 1st and 3rd pulls, but not the
    # skipped one.
    synchronized = @pulls.map { |pr| pr.reload.mergeable }
    assert_equal [nil, true, nil], synchronized
  end

  test "retries synchronize! when lock cannot be acquired", skip_enterprise: true do
    Spokesd.enable_spokesd

    PullRequest.expects(:find_compliant_pull_request_ids).with(anything).returns([@pulls[0].id])
    # first attempt that erorrs
    PullRequest.any_instance.expects(:synchronize!).with(has_entries(lock_options: { strict: true, timeout: 1 })).raises(PullRequest::SynchronizationDependency::LockAcquisitionError)
    # second retry without strict locking
    PullRequest.any_instance.expects(:synchronize!).with(has_entries(lock_options: { strict: false, timeout: 1 }))

    PullRequest.synchronize_requests_for_ref(@source, "master", @owner)
  end

  test "skips synchronize! when base ref is pushed and PR is not merged" do
    enable_feature_flag(:skip_base_ref_syncs_if_not_merged)
    events = subscribe "pull_request.synchronize"

    base_ref = @source.heads.find("master")
    before_sha = base_ref.sha

    # indirectly merge 1 PR - we should continue to run PR sync for this PR and skip the other 2
    merged_pull = @pulls.first
    merged_pull.repository.fetch_commits_from_network(merged_pull.head_repository, merged_pull.head_sha)
    merged_pull.create_merge_commit
    merge_commit_sha = merged_pull.reload.merge_commit_sha
    base_ref.update(merge_commit_sha, @owner)

    Spokesd.enable_spokesd

    refute merged_pull.reload.merged?
    perform_enqueued_jobs(only: [PullRequestSynchronizationJob, SynchronizePullRequestJob]) do
      PullRequest.synchronize_requests_for_ref(@source, "master", @owner, before: before_sha, after: merge_commit_sha)
    end

    # we clear the mergeable flag on all PRs
    synchronized = @pulls.map { |pr| pr.reload.mergeable }
    assert_equal [nil, nil, nil], synchronized

    # we skip the two non-merged PRs
    assert_dogstats_increment(2, "pull_request.sync.skipped_base_ref_sync")

    # we only run Synchronize on the indirectly merged PR
    assert merged_pull.reload.merged?
  end
end

class PullRequestSynchronizeReviewThreadPositionsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, from_example: :pull_request_source, owner: @user)
    @pull_request = create(
      :pull_request,
      user: @user,
      repository: @repo,
      base_ref: "master",
      base_sha: "a270ea0fdfba2bd5a33934e5184784cddce87f38",
      head_ref: "topic-partial-merge",
      head_sha: "948a3b08cbce11ee0df1687b04defacadd11fce3",
    )

    @thread1 = create(:pull_request_review_thread, :on_line, pull_request: @pull_request)
    @thread2 = create(:pull_request_review_thread, :on_line, pull_request: @pull_request)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context "#save_review_thread_positions" do
    test "persists changes to `commit_id` and `position`" do
      new_head_sha = "480d4f47447129f015cb327536c522ca683939a1"
      @pull_request.head_sha = new_head_sha
      @pull_request.line_review_threads.each.with_index do |review_thread, index|
        review_thread.position += index
        review_thread.commit_id = new_head_sha
      end

      # When each record has different changes, expect one query per record.
      assert_queries_matching(/UPDATE `pull_request_review_threads`/, 2) do
        @pull_request.save_review_thread_positions
      end

      assert_equal @thread1.reload.commit_id, new_head_sha
      assert_equal @thread2.reload.commit_id, new_head_sha
    end

    test "persists changes to `commit_id` only" do
      enable_feature_flag(:pull_request_sync_batch_update_thread_positions)

      new_head_sha = "480d4f47447129f015cb327536c522ca683939a1"
      @pull_request.head_sha = new_head_sha
      @pull_request.line_review_threads.each do |review_thread|
        review_thread.commit_id = new_head_sha
      end

      # When all records have only changed the `commit_id`, expect one query
      # per hundred records.
      assert_queries_matching(/UPDATE `pull_request_review_threads`/, 1) do
        @pull_request.save_review_thread_positions
      end

      assert_equal @thread1.reload.commit_id, new_head_sha
      assert_equal @thread2.reload.commit_id, new_head_sha
    end
  end
end

class PullRequestSynchronizeConflictingMergedEventPullRequestTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    @owner = create(:user)
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    @issue = create(:issue, user: @forker, repository: @source)
    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@forker}:topic",
      user: @forker,
      issue: @issue,
      draft: true,
    )

    @pull.ready_for_review!(user: @pull.user)
    @pull.create_issue_event(:merged, @forker, commit_id: @pull.head_sha)

    # Stub the sync job to always think the head branch is merged into the base
    spokes_api = T.must(@pull.base_repository).spokes_api
    @pull.base_repository.stubs(:spokes_api).returns(FakeSpokesApiAlwaysMerged.new(spokes_api))
  end

  class FakeSpokesApiAlwaysMerged
    def initialize(spokes_api)
      @spokes_api = spokes_api
    end

    delegate_missing_to :@spokes_api

    def ahead_behind_contains(base:, tips:)
      tips
    end
  end
  private_constant :FakeSpokesApiAlwaysMerged

  test "succeeds when a merged event already exists for the pull request and the pull request should be marked as merged" do
    Spokesd.enable_spokesd

    assert @pull.issue.events.merges.first.present?

    assert_nothing_raised do
      @pull.synchronize!(
        user: @forker,
        repo: @source,
      )
    end
  end

  test "logs conflict of already created merged issue event to Datadog" do
    Spokesd.enable_spokesd

    assert_difference -> {
      GitHub.dogstats.increments("pull_request.mark_as_merged.record_not_unique").length
    }, 1 do
      @pull.synchronize!(user: @owner, repo: @source)
    end
  end

  test "persists the conflict and supporting information about the pull request to GitHub logs" do
    Spokesd.enable_spokesd

    GitHub.logger.stubs(:info).returns(true)
    GitHub.logger.expects(:info).with(
      "Pull Request attempted to persist 'merged' issue event when one already exists for the same sha",
      "gh.repo.id": @pull.repository_id,
      "gh.pull_request.id": @pull.id,
      "gh.pull_request.merge_commit_sha": @pull.merge_comparison.head_sha,
      "gh.pull_request.base_sha_on_merge": nil,
    )

    @pull.synchronize!(user: @owner, repo: @source)
  end
end
