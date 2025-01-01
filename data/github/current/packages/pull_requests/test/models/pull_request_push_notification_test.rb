# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestPushNotificationTest < GitHub::TestCase
  include RepositoriesTestHelper
  include HydroMessageJobTestHelpers
  include PushTestHelper

  fixtures do
    @defunkt = create(:user, :verified, login: "defunkt")
    @org = create(:organization, admin: @defunkt, login: "acme")
    @subscribed_user = create(:user, :verified, login: "subscriber", email: "subscriber@example.com")

    @repo = create(:repository, owner: @org, name: "widgets", from_example: :rebase_pull_request)
    @repo.add_member @defunkt
    @repo.add_member @subscribed_user
    @defunkt.watch_repo @repo
    @subscribed_user.watch_repo @repo

    # some tests modify repo, so restore to this point before each test
    example_repo_snapshot

    issue = create(:issue, repository: @repo, user: @defunkt)

    @pull = create :pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: issue,
      user: @defunkt

    @before = "325d95e767aca5bf139ea7ce4904e8baedfe3d0d"
    @after = "1968aab83ed37699fbc463d9f3ef40158ee597a4"
    @ref = "refs/heads/contrib"

    @message = {
      before: @before,
      after: @after,
      ref: @ref,
      repo: @repo.name,
      user: @org.login,
      pusher: @defunkt.login,
      pushed_at: Time.now.to_s,
    }
  end

  setup do
    clear_enqueued_jobs
  end

  teardown do
    # restore repo snapshot to reset changes
    example_repo_restore
  end

  def trigger_push(message = @message, repo = @repo, pull = @pull)
    ActionMailer::Base.deliveries.clear
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      trigger_push_event(
        repo.shard_path,
        @defunkt.login,
        [[message[:ref], message[:before], message[:after]]],
        Time.current
      )
    end

    only = [Newsies::DeliverNotificationsJob, AsyncNewsiesDeliveryJob]
    perform_enqueued_jobs(only: only)
    perform_enqueued_jobs # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    @push = push_accessor.latest_for_repo(repository_id: repo.id)
    @pr_push_notification = PullRequestPushNotification.new \
      pull_request: pull,
      before: @before,
      after: @after,
      ref: @ref,
      pushed_at: Time.parse(message[:pushed_at]),
      pusher: @defunkt

  end

  context ".find_by_id" do
    test "initiates a notification with the given compound key" do
      trigger_push
      compound_id = "Pull##{ @pull.id }Before##{ @before }After##{ @after }PushedAt##{ @message[:pushed_at].to_i }Pusher##{ @defunkt.id }"
      prrn = PullRequestPushNotification.find_by_id(compound_id)
      assert_equal @pull, prrn.pull_request
    end

    test "initiates a notification with the given compound key across repositories" do
      forker = create(:user, login: "forker")

      required_jobs = [
        AddToSearchIndexJob,
        DeliverHookEventJob,
        Newsies::AutoSubscribeUsersToRepositoryJob,
        ProcessEventJob,
        RemoveFromSearchIndexJob,
        RepositoryOrchestrationJob,
        UpdateEventFeedsJob
      ]
      forked_repo = perform_enqueued_jobs(only: required_jobs) { fast_fork_repo(@repo, owner: forker, example: :rebase_pull_request) }

      issue = create(:issue, user: forker, repository: @repo)

      forked_pull = PullRequest.create_for!(@repo,
        base: "master",
        head: "#{forked_repo.user}:contrib",
        user: issue.user,
        issue: issue)

      forked_message = {
        before: @before,
        after: @after,
        ref: "refs/heads/contrib",
        repo: forked_repo.name,
        user: forker.login,
        pusher: forker.login,
        pushed_at: Time.now.to_s,
      }

      trigger_push(forked_message, forked_repo, forked_pull)

      compound_id = "Pull##{ forked_pull.id }Before##{ @before }After##{ @after }PushedAt##{ forked_message[:pushed_at].to_i }Pusher##{ forker.id }"
      prrn = PullRequestPushNotification.find_by_id(compound_id)

      assert_equal forked_pull, prrn.pull_request
    end

    test "returns nil if given an invalid compound key" do
      assert_nil PullRequestPushNotification.find_by_id 42
    end

    test "returns nil if the pull request doesn't exist" do
      trigger_push

      bad_id = PullRequest.maximum(:id) + 1

      compound_id = "Pull##{ bad_id }Before##{ @before }After##{ @after }PushedAt##{ @message[:pushed_at].to_i }Pusher##{ @defunkt.id }"
      assert_nil PullRequestPushNotification.find_by_id(compound_id)
    end

    test "returns nil if the push doesn't exist" do
      trigger_push
      bad_id = -1
      assert_nil PullRequestPushNotification.find_by_id "Pull##{ @pull.id }Push##{ bad_id }"
    end
  end

  context "#permalink" do
    test "links to the PR diff for the push" do
      trigger_push
      assert_match %r{/acme/widgets/pull/1/files/325d95e767aca5bf139ea7ce4904e8baedfe3d0d\.\.1968aab83ed37699fbc463d9f3ef40158ee597a4\z},
        @pr_push_notification.permalink
    end
  end

  context "#message_id" do
    test "is unique for the pull request / push combination" do
      trigger_push
      assert_equal "<acme/widgets/pull/1/before/#{@before}/after/#{@after}@#{GitHub.host_name}>",
        @pr_push_notification.message_id
    end
  end

  context "#body" do
    test "describes the push" do
      trigger_push
      assert_equal "@defunkt pushed 2 commits.", @pr_push_notification.body
    end

    test "falls back to 'Somebody' if pusher is missing" do
      trigger_push
      @pr_push_notification.stubs(:user).returns(nil)
      assert_equal "Somebody pushed 2 commits.", @pr_push_notification.body
    end
  end
end
