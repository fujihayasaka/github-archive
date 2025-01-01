# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroPullRequestsOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user)
    @repository.add_member @user
  end

  setup do
    example_repo :post_receive_job_test, @repository

    Spokesd.enable_spokesd

    @commit_sha_before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
    @commit_sha_after = "63611721afd41f58f801d66e543d8288b4c5eb44"
    @branch = "master"
    @ref = "refs/heads/master"
    @updates = [Git::Ref::Update.new(repository: @repository, refname: @ref, before_oid: @commit_sha_before, after_oid: @commit_sha_after)]

    @time = Time.now
    @message = {
      repository_id: @repository.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      ref_updates: @updates.map { |u| { ref: u.refname, before: u.before_oid, after: u.after_oid } },
      pushed_at: @time,
      pusher: @user.login,
      run_hydro_job: true,
    }
  end

  test "enqueues a pull request synchronization job" do
    args = [@repository, "refs/heads/master", @user, forced: false, before: @commit_sha_before, after: @commit_sha_after, push_options: [], excluded_pull_ids: nil, pushed_at: @time]
    assert_enqueued_with(job: PullRequestSynchronizationJob, args: args) do
      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_pull_requests_on_push")
    end
  end

  test "does not (yet) change pull request state when the 'pull.ready' push option is present" do
    pull = PullRequest.create_for(
      @repository,
      title: "Pull needs an update",
      body: "create an update",
      user: @user,
      base: "master",
      head: "topic-fast-forward",
      reviewable_state: "ready"
    )

    update = Git::Ref::Update.new(repository: @repository, refname: "refs/heads/topic-fast-forward", before_oid: @commit_sha_before, after_oid: @commit_sha_after)
    message = @message.merge({
      ref_updates: [{ ref: update.refname, before: update.before_oid, after: update.after_oid }],
      push_options: Hydro::EntitySerializer.push_options(["pull.ready"]),
    })

    only = [PullRequestSynchronizationJob, SynchronizePullRequestJob]
    perform_enqueued_jobs(only: only) do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_pull_requests_on_push")
    end

    assert pull.reload.ready_state?
  end

  if GitHub.merge_queues_enabled?
    test "triggers an update on the merge queue if there was a push directly to the protected branch by an admin" do
      enable_feature_flag(:merge_queue, @repository)
      create(:merge_queue, repository: @repository, branch: @repository.default_branch)

      MergeQueues.expects(:execute!).once
      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_pull_requests_on_push")
    end

    test "does not update the merge queue if context says push is from the merge queue and feature flag is on" do
      enable_feature_flag(:merge_queue, @repository)
      create(:merge_queue, repository: @repository, branch: @repository.default_branch)

      # this context is automatically set when we call `merge_if_possible` from the grouper, but since we don't have
      # groups here we are mimicking this behavior
      GitHub.context.push(from_merge_queue: true)

      MergeQueues.expects(:execute!).never
      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_pull_requests_on_push")
    end
  end

  test "doesn't update the merge queue on delete" do
    enable_feature_flag(:merge_queue, @repository)
    create(:merge_queue, repository: @repository, branch: @repository.default_branch)

    update = Git::Ref::Update.new(repository: @repository, refname: "refs/heads/master", before_oid: @commit_sha_before, after_oid: GitHub::NULL_OID)

    MergeQueues.expects(:execute!).never
    perform_hydro_message_job(
      @message.merge({ ref_updates: [{ ref: update.refname, before: update.before_oid, after: update.after_oid }] }),
      schema: "github.repositories.v1.Pushed",
      queue: "hydro_pull_requests_on_push"
    )
  end unless GitHub.enterprise?

  test "creates closure and restoration issue events when ref is deleted and restored" do
    pull = PullRequest.create_for(
      @repository,
      title: "Pull needs an update",
      body: "create an update",
      user: @user,
      base: "master",
      head: "topic-fast-forward",
      reviewable_state: "ready"
    )

    assert pull.open?

    # delete the ref
    update = Git::Ref::Update.new(repository: @repository, refname: "refs/heads/topic-fast-forward", before_oid: pull.head_sha, after_oid: GitHub::NULL_OID)
    perform_hydro_message_job(
      @message.merge({ ref_updates: [{ ref: update.refname, before: update.before_oid, after: update.after_oid }] }),
      schema: "github.repositories.v1.Pushed",
      queue: "hydro_pull_requests_on_push"
    )

    assert pull.reload.closed?
    assert_equal 2, pull.events.count
    assert pull.events.find_by(event: "head_ref_deleted")
    assert pull.events.find_by(event: "closed")

    # restore the ref
    update = Git::Ref::Update.new(repository: @repository, refname: "refs/heads/topic-fast-forward", before_oid: GitHub::NULL_OID, after_oid: pull.head_sha)
    perform_hydro_message_job(
      @message.merge({ ref_updates: [{ ref: update.refname, before: update.before_oid, after: update.after_oid }] }),
      schema: "github.repositories.v1.Pushed",
      queue: "hydro_pull_requests_on_push"
    )

    assert pull.reload.closed?
    assert_equal 3, pull.events.count
    assert pull.events.find_by(event: "head_ref_deleted")
    assert pull.events.find_by(event: "closed")
    assert pull.events.find_by(event: "head_ref_restored")
  end

  test "queues PullRequestSynchronizationJob with correct forced: value for multiple ref updates" do
    perform_enqueued_jobs only: [RepositoryOrchestration] do
      pull = PullRequest.create_for(
        @repository,
        title: "Pull needs an update",
        body: "create an update",
        user: @user,
        base: "master",
        head: "topic-fast-forward",
        reviewable_state: "ready"
      )
    end

    message = @message.merge({
      ref_updates: [{ ref: "refs/heads/totally-different", before: SecureRandom.hex(20), after: SecureRandom.hex(20) },
              { ref: "refs/heads/topic-fast-forward", before: @commit_sha_before, after: @commit_sha_after }]
    })

    perform_enqueued_jobs only: [RepositoryOrchestration] do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_pull_requests_on_push")
    end

    enqueued_pr_jobs = enqueued_jobs.select { |job| job[:job] == PullRequestSynchronizationJob }
    assert_equal 2, enqueued_pr_jobs.size

    topic_fast_forward_ref = enqueued_pr_jobs.find { |job| job[:args][1] == "refs/heads/topic-fast-forward" }
    totally_different_ref = enqueued_pr_jobs.find { |job| job[:args][1] == "refs/heads/totally-different" }
    refute topic_fast_forward_ref[:args][3]["forced"]
    assert totally_different_ref[:args][3]["forced"]
  end

  test "enqueues handle matching pull requests" do
    args = [@repository.id, before: @commit_sha_before, after: @commit_sha_after, ref: @ref, pushed_at: @time, pusher: @user]

    assert_enqueued_with(job: PushHandleMatchingPullRequestsJob, args: args) do
      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_pull_requests_on_push")
    end
  end
end
