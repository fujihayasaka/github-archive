# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestAssociationsTest < GitHub::TestCase
  include RepositoriesTestHelper
  include NotifydTestHelper
  include HydroTestHelpers

  fixtures do
    @ryan   = create(:user, :verified, email: "rtomayko@gmail.com", login: "rtomayko")
    @owner  = create(:user, :verified, login: "owner", plan: "micro")
    @source = create(:repository, owner: @owner, name: "Source-Repository", from_example: :pull_request_source)
    @owner.watch_repo @source
    @forker = create(:user, :verified, :verified, login: "forker")
    @drama  = create(:user, :verified, login: "jdrama", email: "drama@example.com")
    @drama.add_email "drama@example.com"
    @turtle = create(:user, :verified, login: "turtle")
    @e      = create(:user, :verified, login: "e")
    @vince  = create(:staff_admin_user, :verified, login: "vince")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)
    @issue =
      create(:issue,
        :subscribed_author,
        user: @forker,
        repository: @source,
        body: "hey @vince look at this real quick",
      )

    @commit = @fork.commits.find(@fork.ref_to_sha("topic"))

    @comm   = create :commit_comment, user: @owner, repository: @fork,
      position: 0, path: "color.js", commit_id: @commit.oid

    example_repo_snapshot

    @commit.freeze
    @comm.freeze
  end

  setup do
    reset_cache
    example_repo_restore
    stub_aqueduct_factory

    @fork.add_member(@source.owner)
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
        user: @source.owner,
      )
    refute_nil @pull.issue
    @issue.pull_request = @pull
  end

  test "mentioning in comments" do
    @pull.save!
    assert !@pull.subscribed?(@turtle)
    assert !@pull.subscribed?(@e)
    assert_performed_with job: SubscribeAndNotifyJob do
      @issue.comments.create(body: "@turtle: did you get up to @e?", user: @owner)
    end
    assert @pull.subscribed?(@turtle)
    assert @pull.subscribed?(@e)
  end

  test "enqueues SubscribeAndNotifyJob with load_mentioned_users true" do
    assert !@pull.subscribed?(@turtle)
    assert !@pull.subscribed?(@e)

    args_expectation = proc do |args|
      assert args.second[:load_mentioned_users]
      assert args.second[:load_mentioned_teams]
      assert_nil args.second[:mentioned_user_ids]
      assert_nil args.second[:mentioned_team_ids]
    end

    @pull.save!
    review = @pull.reviews.create!(
      user: @owner,
      head_sha: @pull.head_sha,
    )

    create(:pull_request_review_comment,
      pull_request: @pull,
      user: @forker,
      commit_id: @pull.head_sha,
      path: "file10",
      original_position: 1,
      body: "@turtle: did you get up to @e?",
      pull_request_review_id: review.id,
    )

    assert_performed_with(job: SubscribeAndNotifyJob, args: args_expectation) do
      review.comment!
    end

    assert @pull.subscribed?(@turtle)
    assert @pull.subscribed?(@e)
  end

  test "comments on the related issue touch the issue and pull request" do
    @pull.save!
    # Ensure we have an explicit older updated_at timestamp for both the issue and PR
    one_week_ago = 1.week.ago
    # Use raw sql calls to ensure ActiveRecord doesn't override our
    # desired updated_at
    @pull.update_attribute(:updated_at, one_week_ago)
    @issue.update_attribute(:updated_at, one_week_ago)

    @issue.reload # reset issue.previous_changes

    assert_equal one_week_ago.to_i, @issue.updated_at.to_i
    assert_equal one_week_ago.to_i, @pull.updated_at.to_i

    perform_enqueued_jobs(only: [IssueOrchestration.job_class, IssueCommentOrchestration.job_class]) do
      @issue.comments.create(body: "here is a new comment", user: @owner)
    end

    refute_equal one_week_ago.to_i, @issue.updated_at.to_i
    refute_equal one_week_ago.to_i, @pull.reload.updated_at.to_i
  end

  test "total_comments counts issue comments and review comments" do
    @pull.save!
    assert_equal 0, @pull.total_comments
    @pull.issue.comments.create(body: "here is a new comment", user: @owner)
    create(:pull_request_review_comment,
      pull_request: @pull,
      user: @forker,
      commit_id: @pull.head_sha,
      path: "file10",
      original_position: 1,
      body: "ship it",
    ).submit!
    @pull.reload

    assert_equal 2, @pull.total_comments
  end

  test "total_comments only includes submitted comments when pull request reviews are enabled" do
    repo = create(:private_repository, owner: @owner, from_example: :pull_request_source)
    repo.add_member @forker, action: :write

    forked = fast_fork_repo(repo, example: :pull_request_fork, owner: @forker)


    issue = create(:issue, user: @forker, repository: repo)

    pull =
      create(:pull_request,
        repository: repo,
        base_repository: repo,
        base_user: repo.owner,
        base_ref: "master",
        head_repository: forked,
        head_user: @forker,
        head_ref: "topic",
        issue: issue,
        user: @forker,
      )

    assert_equal 0, pull.total_comments
    pull.issue.comments.create(body: "here is a new comment", user: @owner)
    create(:pull_request_review_comment,
      pull_request: pull,
      user: @forker,
      commit_id: pull.head_sha,
      path: "file10",
      original_position: 1,
      body: "ship it",
    )
    pull.reload

    assert_equal 1, pull.total_comments
  end

  test "generates proper url from comparison" do
    url_prefix = "https://#{GitHub.host_name}/owner/#{@source}/pull/#{@pull.number}"
    assert_equal "#{url_prefix}.patch", @pull.comparison.to_patch_url
    assert_equal "#{url_prefix}.diff",  @pull.comparison.to_diff_url
  end

  test "instruments issue.create event when opening with a pull request" do
    events = subscribe "issue.create"
    pull = perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      PullRequest.create_for! @source,
        base: "owner:master",
        head: "forker:topic",
        user: @forker,
        title: @issue.title,
        body: @issue.body
    end

    expected_payload = {
      issue_id: pull.issue.id,
      repo: @source.name_with_owner,
      repo_id: @source.id,
      public_repo: @source.public?,
      user: @forker.login,
      user_id: @forker.id,
      pull_request_id: pull.id,
      pull_request_url: pull.permalink,
      pull_request_title: pull.title,
      task_list: false,
      private: false,
      spammy: false,
      allowed: false,
    }.merge(pull.issue.event_analytics_payload)

    assert event = events.pop, "expected an instrumenation event"
    assert_subset_hash expected_payload, event.payload
  end

  unless GitHub.enterprise?
    context "Hydro Instrumentation" do
      include HydroTestHelpers

      test "pull request create event is published to hydro" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        actor = create(:user, login: "actor")
        repo = create(:public_repository, owner: actor, from_example: :pull_request_source)
        fork = fast_fork_repo(repo, example: :pull_request_fork, owner: @forker)

        pull = PullRequest.create_for!(repo,
          user: @forker,
          base: "#{repo.owner.login}:master",
          head: "#{@forker.login}:topic",
          title: "testing pull request",
          body: "just some thing",
        )
        changed_files = pull.changed_files_for_instrumentation.map { |file| Hydro::EntitySerializer.changed_file(file, overrides: { change_type: file.change_type_symbol }) }
        msg = {
          pull_request: Hydro::EntitySerializer.pull_request(pull, overrides: { changed_files: changed_files }),
          issue: Hydro::EntitySerializer.issue(pull.issue),
          actor: Hydro::EntitySerializer.user(pull.user),
          repository: Hydro::EntitySerializer.repository(pull.repository),
          repository_owner: Hydro::EntitySerializer.user(pull.repository.owner),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(GitHub.context[:spamuri_form_signals]),
          title: pull.title,
          body: pull.body,
          head_repository: Hydro::EntitySerializer.repository(fork),
          feature_flags: repo.pull_request_create_feature_flags,
        }

        with_hydro_publisher(GitHub.low_latency_hydro_publisher) do
          assert_hydro_published(msg, schema: "github.v1.PullRequestCreate")
        end
      end

      test "pull request merge event is published to hydro" do
        actor = create(:user, login: "actor")
        repo = create(:public_repository, owner: actor, from_example: :pull_request_source)
        fork = create(:fork_repository, forker: @forker, fork_repo: repo, from_example: :pull_request_fork)

        pull = PullRequest.create_for!(repo,
          user: @forker,
          base: "#{repo.owner.login}:master",
          head: "#{@forker.login}:topic",
          title: "testing pull request",
          body: "just some thing",
        )
        result = pull.merge
        assert result[0], "PR merged successfully"

        changed_files = pull.changed_files_for_instrumentation.map { |file| Hydro::EntitySerializer.changed_file(file, overrides: { change_type: file.change_type_symbol }) }
        msg = {
          pull_request: Hydro::EntitySerializer.pull_request(pull, overrides: { changed_files: changed_files }),
          issue: Hydro::EntitySerializer.issue(pull.issue),
          actor: Hydro::EntitySerializer.user(pull.user),
          author: Hydro::EntitySerializer.user(pull.user),
          actor_profile_location: "",
          repository: Hydro::EntitySerializer.repository(pull.repository),
          repository_owner: Hydro::EntitySerializer.user(pull.repository.owner),
          opener_login: @forker.login,
          opener_profile_location: "",
          merge_commit_sha: result[1],
        }
        assert_hydro_published(msg, schema: "github.v1.PullRequestMerge", ignore_extra_keys: true)
        refute_hydro_messages(schema: "github.v1.PullRequestClose")
      end

      test "pull request reopen event is published to hydro" do
        Spokesd.enable_spokesd

        actor = create(:user, login: "actor")
        repo = create(:public_repository, owner: actor, from_example: :pull_request_source)
        fork = create(:fork_repository, forker: @forker, fork_repo: repo, from_example: :pull_request_fork)

        pull = PullRequest.create_for!(repo,
          user: @forker,
          base: "#{repo.owner.login}:master",
          head: "#{@forker.login}:topic",
          title: "testing pull request",
          body: "just some thing",
        )
        pull.close
        assert pull.issue.open(actor)

        msg = {
          pull_request: Hydro::EntitySerializer.pull_request(pull),
          issue: Hydro::EntitySerializer.issue(pull.issue),
          actor: Hydro::EntitySerializer.user(actor),
          repository: Hydro::EntitySerializer.repository(pull.repository),
          repository_owner: Hydro::EntitySerializer.user(pull.repository.owner),
        }

        assert_hydro_published(msg, schema: "github.v1.PullRequestReopen")
      end

      test "pull request close without merge is published to hydro" do
        actor = create(:user, login: "actor")
        repo = create(:public_repository, owner: actor, from_example: :pull_request_source)
        fork = create(:fork_repository, forker: @forker, fork_repo: repo, from_example: :pull_request_fork)

        pull = PullRequest.create_for!(repo,
          user: @forker,
          base: "#{repo.owner.login}:master",
          head: "#{@forker.login}:topic",
          title: "testing pull request",
          body: "just some thing",
        )
        result = pull.close(actor)
        msg = {
          pull_request: Hydro::EntitySerializer.pull_request(pull),
          issue: Hydro::EntitySerializer.issue(pull.issue),
          actor: Hydro::EntitySerializer.user(actor),
          repository: Hydro::EntitySerializer.repository(pull.repository),
          repository_owner: Hydro::EntitySerializer.user(pull.repository.owner),
        }

        assert_hydro_published(msg, schema: "github.v1.PullRequestClose")
        refute_hydro_messages(schema: "github.v1.PullRequestMerge")
      end

      test "pull request merge hydro event has truncated merge commit message" do
        actor = create(:user, login: "actor")
        repo = create(:public_repository, owner: actor, from_example: :pull_request_source)
        fork = create(:fork_repository, forker: @forker, fork_repo: repo, from_example: :pull_request_fork)

        pull = PullRequest.create_for!(repo,
          user: @forker,
          base: "#{repo.owner.login}:master",
          head: "#{@forker.login}:topic",
          title: "testing pull request",
          body: "just some thing",
        )

        PullRequest::AnalyticsDependency.stub_const(:HYDRO_MAX_MERGE_COMMIT_MESSAGE_LENGTH, 50) do
          message = "a" * 51
          result = pull.merge(message: message)
          assert result[0], "PR merged successfully"

          changed_files = pull.changed_files_for_instrumentation.map { |file| Hydro::EntitySerializer.changed_file(file, overrides: { change_type: file.change_type_symbol }) }
          expected_msg = {
            pull_request: Hydro::EntitySerializer.pull_request(pull, overrides: { changed_files: changed_files }),
            issue: Hydro::EntitySerializer.issue(pull.issue),
            actor: Hydro::EntitySerializer.user(pull.user),
            author: Hydro::EntitySerializer.user(pull.user),
            actor_profile_location: "",
            repository: Hydro::EntitySerializer.repository(pull.repository),
            repository_owner: Hydro::EntitySerializer.user(pull.repository.owner),
            opener_login: @forker.login,
            opener_profile_location: "",
            merge_commit_sha: result[1],
            merge_commit_message: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...",
          }

          assert_hydro_published(expected_msg, schema: "github.v1.PullRequestMerge", ignore_extra_keys: true)
        end
      end
    end
  end

  test "creates a PullRequestEvent when opening with a pull request" do
    T.unsafe(GitHub).reset_stratocaster
    only = [ProcessEventJob, SubscribeAndNotifyJob, IssueOrchestration.job_class]
    pull = perform_enqueued_jobs(only: only) do
      PullRequest.create_for! @source,
        base: "owner:master",
        head: "forker:topic",
        user: @forker,
        title: @issue.title,
        body: @issue.body
    end

    assert_equal [], pull.errors.to_a
    assert pull.valid?
    assert event = GitHub.stratocaster_store.last
    assert_equal "PullRequestEvent", event.event_type
    assert_equal :opened, event.payload["action"]
    assert pull.subscribed?(@forker)
  end

  test "events when opening a pull request from an existing issue" do
    T.unsafe(GitHub).reset_stratocaster
    only = [ProcessEventJob]
    pull = perform_enqueued_jobs(only: only) do
      PullRequest.create_for! @source,
        base: "owner:master",
        head: "forker:topic",
        user: @forker,
        issue: @issue
    end

    assert_equal [], pull.errors.to_a
    assert pull.valid?
    assert event = GitHub.stratocaster_store.last
    assert_equal "PullRequestEvent", event.event_type
    assert_equal :opened, event.payload["action"]
    assert pull.subscribed?(@forker)
  end

  test "instruments when opening a pull request from an existing issue" do
    events = subscribe "issue.transform_to_pull"
    pull =
      PullRequest.create_for! @source,
        base: "owner:master",
        head: "forker:topic",
        user: @forker,
        issue: @issue

    assert_equal [], pull.errors.to_a
    assert pull.valid?
    assert event = events.pop, "event expected"
  end

  test "removes issue from the search index when opening a pull request from an existing issue" do
    now = Time.now
    timestamp = Timestamp.from_time(now)
    Timecop.freeze(now) do
      # We current end up enqueueing this twice, ones through the path that the pull
      # request is created and once through the path that the issue is updated and also
      # triggers a sync of the associated pull request.
      assert_enqueued_jobs 2, only: AddToSearchIndexJob, queue: "index_high" do
        assert_enqueued_jobs 1, only: RemoveFromSearchIndexJob, queue: "index_high" do
          pull = perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
            PullRequest.create_for! @source,
              base: "owner:master",
              head: "forker:topic",
              user: @forker,
              issue: @issue
          end

          pull_guid = AddToSearchIndexJob.guid("pull_request", pull.id)

          assert_enqueued_with(job: AddToSearchIndexJob, args: ["pull_request", pull.id, { "submitted_at" => timestamp, "guid" => pull_guid }], queue: "index_high")
          assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["issue", @issue.id, @issue.repository_id], queue: "index_high")
        end
      end
    end
  end

  test "subscriptions when attaching a pull request to an issue" do
    @fork.add_member(@ryan)
    pull =
      PullRequest.create_for! @source,
        base: "owner:master",
        head: "forker:topic",
        user: @ryan,
        issue: @issue

    assert_equal [], pull.errors.to_a
    assert pull.valid?
    assert pull.subscribed?(@forker) # issue author
    assert pull.subscribed?(@ryan)
  end

  test "notifications when opening a pull request", feature_disabled: :notifyd_pull_request_notify_email_and_web do
    GitHub.newsies.get_and_update_settings(@vince) do |settings|
      settings.participating_settings << "email"
    end
    deliveries = ActionMailer::Base.deliveries.size
    only = [AddToSearchIndexJob]
    pull = perform_enqueued_jobs(only: only) do
      only = [AddToSearchIndexJob, DeliverHookEventJob, MaintainTrackingRefJob, Newsies::DeliverNotificationsJob, NotifySubscriptionStatusChangeJob, ProcessEventJob, SubscribeAndNotifyJob, UpdateCloseIssueReferencesJob, UpdateEventFeedsJob, AsyncNewsiesDeliveryJob]
      perform_enqueued_jobs(only: only) do
        PullRequest.create_for!(@source,
          base: "owner:master",
          head: "forker:topic",
          user: @forker,
          title: @issue.title,
          body: @issue.body,
        )
      end
    end
    assert_equal deliveries + 2, ActionMailer::Base.deliveries.size

    mail = ActionMailer::Base.deliveries.last
    assert_match "[owner/Source-Repository] #{@issue.title} (", mail.subject
    assert_match "You can view, comment on, or merge this pull request online at:\r\n\r\n  https://#{GitHub.host_name}/owner/Source-Repository/pull/2", mail.encoded
    assert_equal pull.message_id, "<#{mail.message_id}>"
  end

  test "notifications when opening a pull request", feature_enabled: :notifyd_pull_request_notify do
    pull = perform_enqueued_jobs(only: [Notifyd::PublishNotifyMessageJob]) do
      PullRequest.create_for!(@source,
        base: "owner:master",
        head: "forker:topic",
        user: @forker,
        title: @issue.title,
        body: @issue.body,
      )
    end

    assert_aqueduct_jobs(queue: "notifyd_notify", app: "notifyd-production")
  end

  test "notifications_thread is the issue" do
    pull = PullRequest.create_for!(@source,
          base: "owner:master",
          head: "forker:topic",
          user: @forker,
          title: @issue.title,
          body: @issue.body,
        )
    assert_equal pull.issue, pull.notifications_thread
  end

  test "find comparison comments" do
    pull = PullRequest.create_for! @source,
      base: "owner:master",
      head: "forker:topic",
      user: @forker,
      title: @issue.title,
      body: @issue.body

    assert_equal [@comm], pull.historical_comparison.comments
  end

  test "find comparison comments visible to viewer" do
    pull = PullRequest.create_for! @source,
      base: "owner:master",
      head: "forker:topic",
      user: @forker,
      title: @issue.title,
      body: @issue.body

    assert_equal [@comm], pull.historical_comparison.comments_for(@forker)
  end

  context "#base_branch_rule_evaluator" do
    test "returns nil when not protected" do
      assert_nil @pull.base_branch_rule_evaluator
    end

    test "returns the branch when protected" do
      branch = create(:protected_branch, repository: @source, name: "master")

      assert_equal branch.id, @pull.base_branch_rule_evaluator.original_protected_branch.id
    end

    test "returns nil when base_repository is not present" do
      @pull.base_repository = nil

      assert_nil @pull.base_branch_rule_evaluator
    end
  end

  context "#head_branch_rule_evaluator" do
    test "returns nil when not protected" do
      assert_nil @pull.head_branch_rule_evaluator
    end

    test "returns the branch when protected" do
      branch = create(:protected_branch, repository: @fork, name: "topic")

      assert_equal branch.id, @pull.head_branch_rule_evaluator.original_protected_branch.id
    end

    test "returns the branch when protected with wildcard defintion" do
      branch = create(:protected_branch, repository: @fork, name: "*")

      assert_equal branch.id, @pull.head_branch_rule_evaluator.original_protected_branch.id
    end
  end
end
