# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMergeQueueProximaExperienceTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    create(:merge_queue_integration)
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:repository, :has_merge_queue, owner: @org)
    @repo.enable_feature(:merge_queue)

    create :hook, :web, installation_target: @repo, events: %w(merge_group pull_request)

    @queue = @repo.default_merge_queue
    @queue.update(merging_strategy: MergeQueues::IConfiguration::GroupingStrategy::HeadGreen.serialize)

    example_repo_snapshot
  end

  setup do
    Spokesd.enable_spokesd

    skip unless GitHub.merge_queues_enabled?
  end

  test "determines the tenant if it's unset" do
    pull = create(:pull_request,
      :with_mergeable_head,
      repository: @repo,
      base_repository: @repo,
      base_ref: @queue.branch,
      head_ref: "cr-line-endings",
      user: @user
    )

    head_sha = pull.head_sha
    check_suite = create(:check_suite, repository: @repo, head_sha: head_sha)
    create(:check_run, :success, check_suite:, display_name: "required-run")
    pull.create_merge_commit
    @queue.enqueue!(pull_request: pull, enqueuer: @user, jump_queue: false)

    jobs = [
      MergeQueuePostMergeJob,
      MergeQueueDisableJob,
      DeliverHookEventJob,
      MergeQueueDeleteRefJob,
    ]

    assert_equal 1, @queue.entries.count
    # Simulate running the job with it blank.
    GitHub::CurrentTenant.set(nil) do
      @repo.reload
      perform_enqueued_jobs(only: jobs) do
        MergeQueueJob.perform_now(@repo, @queue.branch)
      end
    end

    pull.reload
    assert pull.merged?
    assert_equal 0, @queue.entries.count
  end
end
