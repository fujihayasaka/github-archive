# typed: true
# frozen_string_literal: true

require "test_helper"

class NotificationSummaryTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
    @issue = create :issue, user: @user, repository: @repo, created_at: 1.year.ago
    @issue2 = create :issue, user: @user, repository: @repo, created_at: 1.month.ago
    @discussion_post = create(:discussion_post)
    @discussion_post_reply = create(:discussion_post_reply)

    # The ghost user is the fallback for anonymous gists, so make sure it exists
    # ahead of tests that try to load the anonymous gist's user.
    User.create_ghost

    gist_content = [{ name: "1", value: "random content" }]
    @gist = GistHelpers.generate(contents: gist_content, user: @user)
    @anonymous_gist = GistHelpers.generate(contents: gist_content, user: nil)
  end

  setup do
    @threshold = NotificationSummary.comment_body_size_threshold
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  teardown do
    NotificationSummary.comment_body_size_threshold = @threshold
  end

  test "#rebuild_summary works with Gist thread" do
    summary = NotificationSummary.new(list: @gist.notifications_list, thread: @gist)
    summary.rebuild_summary(save_record: false)

    assert_equal @gist.title, summary.title
    assert_equal @gist.user_id, summary.creator_id
  end

  test "#rebuild_summary works with CheckSuite thread" do
    github_app = create(:integration, name: "Some App")
    check_suite = create(:check_suite, :success, name: "Tests", github_app: github_app)
    summary = NotificationSummary.new(list: check_suite.repository, thread: check_suite)

    summary.rebuild_summary(save_record: false)

    branch_name = check_suite.head_branch
    assert_equal summary.title, "Tests workflow run succeeded for #{branch_name} branch"
    assert_equal summary.authors.keys, [check_suite.creator_id.to_s]
    assert_equal summary.number, check_suite.id
    assert_equal summary.check_suite_conclusion, check_suite.conclusion
  end

  test "#rebuild_summary works with Actions::WorkflowRun thread" do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner

    check_suite = create(:check_suite_for_actions_app, :failure, repository: @repo)
    workflow_run = check_suite.workflow_run
    summary = NotificationSummary.new(list: workflow_run.repository, thread: workflow_run)

    summary.rebuild_summary(save_record: false)

    assert_equal summary.title, "#{workflow_run.creator.display_login} requested your review to deploy to an environment"
    assert_equal summary.authors.keys, [workflow_run.creator_id.to_s]
    assert_equal summary.number, workflow_run.id
  end

  test "#rebuild_summary works with SecurityAdvisory thread" do
    make_trusted_oauth_apps_owner
    @repo.enable_vulnerability_alerts(actor: @user)

    # Our vulnerability came out in the past
    Timecop.freeze(1.month.ago) do
      @vulnerability = create :security_advisory
      @vulnerability_alerting_event = create(
        :vulnerability_alerting_event,
        :on_process_alerts, {
          vulnerability: @vulnerability,
        }
      )
    end

    summary = NotificationSummary.new(list: @user, thread: @vulnerability)
    summary.rebuild_summary(save_record: false)
    assert_match /A security vulnerability in rake affects at least one of your repositories/, summary.title
  end

  test "#rebuild_summary works with SecurityAdvisory thread and the alerting event is missing" do
    make_trusted_oauth_apps_owner
    @repo.enable_vulnerability_alerts(actor: @user)

    # Our vulnerability came out in the past
    Timecop.freeze(1.month.ago) do
      @vulnerability = create :security_advisory
    end

    summary = NotificationSummary.new(list: @user, thread: @vulnerability)
    summary.rebuild_summary(save_record: false)
    assert_match /A security vulnerability in rake affects at least one of your repositories/, summary.title
  end

  test "#rebuild_summary works with RepositoryDependabotAlertsThread thread" do
    owner = make_trusted_oauth_apps_owner
    @repo.enable_vulnerability_alerts(actor: @user)

    # Our vulnerability came out in the past
    Timecop.freeze(1.month.ago) do
      @vulnerability = create :published_vulnerability
      @vulnerability_alerting_event = create(
        :vulnerability_alerting_event,
        :on_initialize, {
          vulnerability: @vulnerability,
          repository: @repo,
        }
      )
    end

    summary = NotificationSummary.new(list: @repo, thread: RepositoryDependabotAlertsThread.new(@repo))
    summary.rebuild_summary(save_record: false)

    assert_equal owner.id, summary.creator_id
    assert_match /Your repository has dependencies with security vulnerabilities/, summary.title
  end

  test "#rebuild_summary works with RepositoryDependabotAlertsThread thread when the alerting event is missing" do
    owner = make_trusted_oauth_apps_owner
    @repo.enable_vulnerability_alerts(actor: @user)

    # Our vulnerability came out in the past
    Timecop.freeze(1.month.ago) do
      @vulnerability = create :published_vulnerability
    end

    summary = NotificationSummary.new(list: @repo, thread: RepositoryDependabotAlertsThread.new(@repo))
    summary.rebuild_summary(save_record: false)

    assert_equal owner.id, summary.creator_id
    assert_match /Your repository has dependencies with security vulnerabilities/, summary.title
  end

  test "#rebuild_summary works with RepositoryVulnerabilityAlert" do
    make_trusted_oauth_apps_owner
    @repo.enable_vulnerability_alerts(actor: @user)

    # Our vulnerability came out in the past
    Timecop.freeze(1.month.ago) do
      @vulnerability = create :published_vulnerability
    end
    range = @vulnerability.vulnerable_version_ranges.first

    alert = create(:repository_vulnerability_alert, {
      repository: @repo,
      vulnerability: @vulnerability,
      vulnerable_version_range: range,
      vulnerable_manifest_path: "http://www.github.com/github/github/gemfile.rb",
      state: "open",
    })

    summary = NotificationSummary.new(list: @repo, thread: alert)
    summary.rebuild_summary(save_record: false)
    assert_match /Potential security vulnerability found in the \w+ dependency/, summary.title
  end

  test "#rebuild_summary with MemexProject" do
    admin = create(:user)
    organization = create(:organization, admin: admin)
    member = create(:verified_user).tap { |u| organization.add_member(u) }
    memex_project = create(:memex_project, owner: organization)
    memex_project_status = create(:memex_project_status, memex_project: memex_project)
    summary = NotificationSummary.new(list: organization, thread: memex_project)

    summary.rebuild_summary(save_record: false)

    assert_equal summary.title, memex_project_status.memex_project.title
    assert_equal summary.number, memex_project_status.memex_project.number
    assert_equal summary.creator_id, memex_project_status.creator_id
    assert_equal summary.authors.keys, [memex_project_status.creator_id.to_s]

    item_key = "MemexProjectStatus:#{memex_project_status.id}"
    item = summary.items[item_key]
    assert_equal item[:permalink], memex_project_status.permalink
  end

  test "recovers from race condition" do
    summ1 = NotificationSummary.new list: @repo, thread: @issue
    summ2 = NotificationSummary.new list: @repo, thread: @issue

    assert_equal summ1, summ1.summarize!(@issue)
    assert_equal summ1, summ2.summarize!(@issue)
  end

  test "logs are emitted when a notification summary is created or updated" do
    output = capture_logs do
      summ1 = NotificationSummary.new list: @repo, thread: @issue

      assert_equal summ1, summ1.summarize!(@issue)
    end
    assert_match "code.namespace=\"NotificationSummary\"", output
    assert_match "code.function=\"save\"", output
    assert_match "gh.notifications.notification_summary.method=\"create\"", output
    assert_includes output, "gh.notifications.notification_summary.id="
  end

  test "ordered_item_keys dont include thread key" do
    summ = NotificationSummary.new list: @repo, thread: @issue
    summ.summarize(@issue)

    # sort items with symbol keys
    assert_equal [], summ.ordered_item_keys
    assert_equal [], summ.oldest_item_keys
  end

  test "truncates body" do
    NotificationSummary.comment_body_size_threshold = 1
    summ = NotificationSummary.fetch_and_update! @repo, @issue, @issue
    summ = NotificationSummary.find summ.id
    assert item = summ.items["Issue:#{@issue.id}"]

    refute_equal @issue.body, item["body"]
    assert_equal @issue.body[0..0], item["body"]
  end

  test "truncates issue bodies for issues that don't respond to body" do
    issue = create(:issue, user: @user, repository: @repo)

    # This is replicating behavior observed in production, that issue instances
    # return false for respond_to?(:body)
    issue.stubs(:respond_to?).returns(false)

    summ = NotificationSummary.fetch_and_update! @repo, issue, issue
    summ = NotificationSummary.find summ.id
    assert item = summ.items["Issue:#{issue.id}"]

    assert_equal issue.body, item["body"]
    assert_equal issue.compressed_body, item["body"]
  end

  test "trims body_html keys" do
    summ = NotificationSummary.fetch_and_update! @repo, @issue, @issue
    summ = NotificationSummary.find summ.id
    assert item = summ.items["Issue:#{@issue.id}"]
    assert item["body"]
    refute_equal "BOOYA", item["body"]
    assert_nil item["body_html"]
    item["body"] = item["body_html"] = item[:body_html] = "BOOYA"

    summ.save!
    summ = NotificationSummary.find summ.id
    assert item = summ.items["Issue:#{@issue.id}"]
    assert_equal "BOOYA", item["body"]
    assert_nil item["body_html"]
  end

  test "trim oldest n keys" do
    comments = []
    6.times do |i|
      comments << create(:issue_comment, user: @user, repository: @repo,
        body: i.to_s,
        issue: @issue, created_at: (100 - i).days.ago)
    end

    summ = NotificationSummary.fetch_and_update!(@repo, @issue, comments.last)

    # sort items with string keys
    summ.items.each do |key, symbol_hash|
      summ.items[key] = symbol_hash.stringify_keys
    end

    # all comments are summarized plus the thread
    assert_equal comments.size + 1, summ.items.size

    # trim the oldest comment
    summ.item_limit = comments.size - 1
    summ.save!
    oldest_comment = comments.shift

    assert_equal comments.size + 1, summ.items.size
    assert summ.items.key?(summ.thread_item_key), "thread item key"
    comments.each do |comment|
      assert summ.items.key?("IssueComment:#{comment.id}"), comment.body
    end

    assert !summ.items.key?("IssueComment:#{oldest_comment.id}")
  end

  # TODO: This test requires that closing an issue triggers a NotificationSummary update
  # test "touches updated_at for issue event notifications" do
  #   summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue)
  #   old_updated_at = summary.updated_at
  #
  #   Timecop.freeze(1.hour.from_now) do
  #     @issue.close
  #
  #     assert summary.reload.updated_at > old_updated_at
  #   end
  # end

  test "gets a commit thread" do
    example_repo :simple, @repo
    commit = @repo.heads.find("master").target

    summary = NotificationSummary.fetch_and_update!(@repo, commit, commit)
    assert_equal @repo,  summary.list
    assert_equal commit, summary.thread
  end

  test "handles a commit thread from a deleted repository" do
    example_repo :simple, @repo
    commit = @repo.heads.find("master").target

    summary = NotificationSummary.fetch_and_update!(@repo, commit, commit)

    @repo.destroy
    summary = NotificationSummary.find(summary.id)  # reloading doesn't clear the memoization

    assert_nil summary.list
    assert_nil summary.thread
  end

  test "sync_thread_read_state with a missing commit" do
    thread_key = ["Grit::Commit", "deadbeef" * 5].join(";")
    summary = NotificationSummary.new(list: @repo, thread_key: thread_key)

    refute summary.sync_thread_read_state(@user)
  end

  test "sync_notifications_changed with a missing commit" do
    thread_key = ["Grit::Commit", "deadbeef" * 5].join(";")
    summary = NotificationSummary.new(list: @repo, thread_key: thread_key)

    refute summary.sync_notifications_changed(@user)
  end

  test "gracefully handles legacy Discussion data" do
    thread_key = "Discussion;1234"
    summary = NotificationSummary.new(list: @repo, thread_key: thread_key)
    assert_nil summary.thread
  end

  test "handles a discussion post thread from a deleted discussion" do
    summary = NotificationSummary.fetch_and_update!(@discussion_post.team, @discussion_post, @discusion_post)
    @discussion_post.delete # don't trigger dependent destroys

    summary = NotificationSummary.find(summary.id)
    assert_nil summary.thread
  end

  context "#summarize" do

    context "AdvisoryCredit" do
      test "summary is correct" do
        credit = create(:advisory_credit, :with_repository_advisory)

        notification_summary = NotificationSummary.new(list: credit.repository_advisory.repository, thread: credit.repository_advisory)
        summary = notification_summary.summarize(credit)
        assert_equal "#{credit.creator.display_login} credited you as an analyst for your contributions to security advisory #{credit.repository_advisory.ghsa_id}.",
          summary[:body]
      end
    end

    context "PullRequest" do
      test "show pull request is in draft state" do
        draft_pull = create(:pull_request, :disable_disk_access, work_in_progress: true)
        summ = NotificationSummary.new list: @discussion_post.team, thread: draft_pull
        summary = summ.summarize!(draft_pull.issue)
        assert summary.is_draft
      end

      test "show pull request is non-draft state" do
        draft_pull = create(:pull_request, :disable_disk_access, work_in_progress: false)
        summ = NotificationSummary.new list: @discussion_post.team, thread: draft_pull
        summary = summ.summarize!(draft_pull.issue)
        refute summary.is_draft
      end
    end

    context "PullRequestPushNotification" do
      test "summarizes the pull request push" do
        repo = create(:repository)
        issue = build(:issue, title: "Pull Request Title", repository: repo, user: repo.owner)
        pull = create(:pull_request, :disable_disk_access, issue: issue, user: repo.owner)
        Repositories::RefUpdate.any_instance.stubs(:large_push?).returns(true)

        summary = NotificationSummary.fetch_and_update!(pull.repository, pull.issue, pull.issue)
        assert_equal summary.title, "Pull Request Title"

        notification = PullRequestPushNotification.new \
                        pull_request: pull,
                        before: "325d95e767aca5bf139ea7ce4904e8baedfe3d0d",
                        after: "1968aab83ed37699fbc463d9f3ef40158ee597a4",
                        ref: "refs/heads/main",
                        pushed_at: Time.now,
                        pusher: create(:user)
        summary = NotificationSummary.fetch_and_update!(pull.repository, pull.issue, notification)

        push_item = summary.items[summary.item_key(notification)]
        assert_equal push_item["body"], notification.body
        assert_equal push_item["permalink"], notification.permalink
      end

      test "removes all existing pull request push notifications if it's a force push" do
        repo = create(:repository)
        issue = build(:issue, title: "Pull Request Title", repository: repo, user: repo.owner)
        pull = create(:pull_request, :disable_disk_access, issue: issue, user: repo.owner)
        Repositories::RefUpdate.any_instance.stubs(:large_push?).returns(true)

        summary = NotificationSummary.fetch_and_update!(pull.repository, pull.issue, pull.issue)
        assert_equal summary.title, "Pull Request Title"

        notification = PullRequestPushNotification.new \
                        pull_request: pull,
                        before: "325d95e767aca5bf139ea7ce4904e8baedfe3d0d",
                        after: "1968aab83ed37699fbc463d9f3ef40158ee597a4",
                        ref: "refs/heads/main",
                        pushed_at: 1.minute.ago,
                        pusher: create(:user)
        summary = NotificationSummary.fetch_and_update!(pull.repository, pull.issue, notification)

        push_item = summary.items[summary.item_key(notification)]
        assert_equal push_item["body"], notification.body
        assert_equal push_item["permalink"], notification.permalink

        Repositories::RefUpdate.any_instance.stubs(:non_fast_forward?).returns(true)
        force_notification = PullRequestPushNotification.new \
                        pull_request: pull,
                        before: "57ff65ddb98d942bc3d28a6c89c9a97f3dd14657",
                        after: "a5133a06cb80255be78cab49ce750238eeb24f89",
                        ref: "refs/heads/main",
                        pushed_at: Time.now,
                        pusher: create(:user)
        force_summary = NotificationSummary.fetch_and_update!(pull.repository, pull.issue, force_notification)

        force_push_item = force_summary.items[force_summary.item_key(force_notification)]
        assert_equal force_push_item["body"], force_notification.body
        assert_equal force_push_item["permalink"], force_notification.permalink

        assert_nil force_summary.items[force_summary.item_key(notification)]
      end

      test "does not remove newer pull request push notifications if it's a force push" do
        repo = create(:repository)
        issue = build(:issue, title: "Pull Request Title", repository: repo, user: repo.owner)
        pull = create(:pull_request, :disable_disk_access, issue: issue, user: repo.owner)
        Repositories::RefUpdate.any_instance.stubs(:large_push?).returns(true)

        summary = NotificationSummary.fetch_and_update!(pull.repository, pull.issue, pull.issue)
        assert_equal summary.title, "Pull Request Title"

        notification = PullRequestPushNotification.new \
                        pull_request: pull,
                        before: "325d95e767aca5bf139ea7ce4904e8baedfe3d0d",
                        after: "1968aab83ed37699fbc463d9f3ef40158ee597a4",
                        ref: "refs/heads/main",
                        pushed_at: Time.now,
                        pusher: create(:user)
        summary = NotificationSummary.fetch_and_update!(pull.repository, pull.issue, notification)

        push_item = summary.items[summary.item_key(notification)]
        assert_equal push_item["body"], notification.body
        assert_equal push_item["permalink"], notification.permalink

        Repositories::RefUpdate.any_instance.stubs(:non_fast_forward?).returns(true)
        force_notification = PullRequestPushNotification.new \
                        pull_request: pull,
                        before: "57ff65ddb98d942bc3d28a6c89c9a97f3dd14657",
                        after: "a5133a06cb80255be78cab49ce750238eeb24f89",
                        ref: "refs/heads/main",
                        pushed_at: 1.minute.ago,
                        pusher: create(:user)
        force_summary = NotificationSummary.fetch_and_update!(pull.repository, pull.issue, force_notification)

        force_push_item = force_summary.items[force_summary.item_key(force_notification)]
        assert_equal force_push_item["body"], force_notification.body
        assert_equal force_push_item["permalink"], force_notification.permalink

        original_push_item = force_summary.items[force_summary.item_key(notification)]
        assert_equal original_push_item["body"], notification.body
        assert_equal original_push_item["permalink"], notification.permalink
      end

      test "summarizes the whole pull request if it's missing" do
        repo = create(:repository)
        issue = build(:issue, title: "Pull Request Title", repository: repo, user: repo.owner)
        pull = create(:pull_request, :disable_disk_access, issue: issue, user: repo.owner)
        Repositories::RefUpdate.any_instance.stubs(:large_push?).returns(true)

        # Ensure hasn't been created yet
        NotificationSummary.delete_all
        refute NotificationSummary.by_thread(pull.repository, pull.issue)

        notification = PullRequestPushNotification.new \
                        pull_request: pull,
                        before: "325d95e767aca5bf139ea7ce4904e8baedfe3d0d",
                        after: "1968aab83ed37699fbc463d9f3ef40158ee597a4",
                        ref: "refs/heads/main",
                        pushed_at: Time.now,
                        pusher: create(:user)
        summary = NotificationSummary.fetch_and_update!(pull.repository, pull.issue, notification)

        # Created the basic info for the thread
        assert_equal summary.title, "Pull Request Title"
        assert summary.is_pull_request

        # Issue item should have been added
        assert summary.items["Issue:#{issue.id}"]

        # Push should have been added
        push_item = summary.items[summary.item_key(notification)]
        assert_equal push_item["body"], notification.body
        assert_equal push_item["permalink"], notification.permalink
      end
    end

    context "DiscussionPost" do
      test "sets the title" do
        summary = NotificationSummary.new list: @discussion_post.team, thread: @discussion_post
        summary.summarize(@discussion_post)

        string = @discussion_post.title
        assert_equal string, summary.title
      end

      test "sets the authors" do
        user = @discussion_post.user

        summary = NotificationSummary.new list: @discussion_post.team, thread: @discussion_post

        assert_empty summary.authors
        summary.summarize(@discussion_post)

        refute_empty summary.authors
        assert_equal user.login, summary.authors[user.id]
      end
    end

    context "DiscussionPostReply" do
      test "summarizes the parent post itself if it has yet to be summarized" do
        summary = NotificationSummary.new(
          list: @discussion_post_reply.team,
          thread: @discussion_post_reply.discussion_post)
        refute summary.title.present?
        refute summary.items.any?

        summary.summarize(@discussion_post_reply)

        assert summary.title.present?
        assert summary.items.any?
      end

      test "summarizes all unsummarized replies" do
        2.times { create(:discussion_post_reply, discussion_post: @discussion_post_reply.discussion_post) }
        summary = NotificationSummary.new(
          list: @discussion_post_reply.team,
          thread: @discussion_post_reply.discussion_post)
        refute summary.items.any?

        summary.summarize(@discussion_post_reply)

        # 1 parent post and 3 replies.
        assert_equal 4, summary.items.size
      end
    end

    context "RepositoryVulnerabilityAlert::WebNotification" do
      test "correctly summarizes the vulnerability alert" do
        make_trusted_oauth_apps_owner
        @repo.enable_vulnerability_alerts(actor: @user)

        # Our vulnerability came out in the past
        Timecop.freeze(1.month.ago) do
          @vulnerability = create :published_vulnerability
        end
        range = @vulnerability.vulnerable_version_ranges.first

        alert = create(:repository_vulnerability_alert, {
          repository: @repo,
          vulnerability: @vulnerability,
          vulnerable_version_range: range,
          vulnerable_manifest_path: "http://www.github.com/github/github/gemfile.rb",
          state: "open",
        })
        notification = RepositoryVulnerabilityAlert::WebNotification.new(alert)

        summary = NotificationSummary.new(list: @repo, thread: alert)
        summary.summarize(notification)
        assert_match /Potential security vulnerability found in the \w+ dependency/, summary.title
      end
    end

    context "VulnerabilityAlertingEvent::SecurityAdvisoryNotification" do
      test "correctly summarizes the security advisory notification" do
        make_trusted_oauth_apps_owner
        @repo.enable_vulnerability_alerts(actor: @user)

        # Our vulnerability came out in the past
        Timecop.freeze(1.month.ago) do
          @vulnerability = create :published_vulnerability
          @vulnerability_alerting_event = create(
            :vulnerability_alerting_event,
            :on_process_alerts, {
              vulnerability: @vulnerability,
            }
          )
        end

        notification = VulnerabilityAlertingEvent::SecurityAdvisoryNotification.new(@user, @vulnerability_alerting_event)

        summary = NotificationSummary.new(list: @user, thread: @vulnerability_alerting_event)
        summary.summarize(notification)
        assert_match /A security vulnerability in rake affects at least one of your repositories/, summary.title
      end
    end

    context "VulnerabilityAlertingEvent::VulnerableRepositoryNotification" do
      test "correctly summarizes the vulnerable repository notification" do
        owner = make_trusted_oauth_apps_owner
        @repo.enable_vulnerability_alerts(actor: @user)

        # Our vulnerability came out in the past
        Timecop.freeze(1.month.ago) do
          @vulnerability = create :published_vulnerability
          @vulnerability_alerting_event = create(
            :vulnerability_alerting_event,
            :on_initialize, {
              vulnerability: @vulnerability,
            }
          )
        end

        notification = VulnerabilityAlertingEvent::VulnerableRepositoryNotification.new(@repo, @vulnerability_alerting_event)

        summary = NotificationSummary.new(list: @user, thread: @repo)
        summary.summarize(notification)

        assert_equal owner.id, summary.creator_id
        assert_match /Your repository has dependencies with security vulnerabilities/, summary.title
      end
    end

    context "GistComment" do
      test "summarizes all unsummarized comments" do
        commenters = [create(:user), create(:user)]
        now = Time.now
        future = now + 1
        Timecop.freeze(future) do

          commenters.each do |user|
            @gist.comments.create(body: "Hi", user: user)
          end
        end
        Timecop.freeze(now) do
          summary = NotificationSummary.new(
            list: @gist.notifications_list,
            thread: @gist)
          refute summary.items.any?

          summary.summarize(@gist.comments.last)

          # 1 parent gist and 2 comments.
          assert_equal 3, summary.items.size

          assert_equal @gist.title, summary.title
          assert_equal @gist.user_id, summary.creator_id
          expected_commenters = commenters.map(&:login)
          expected_commenters << @gist.user.login
          assert_same_elements expected_commenters, summary.authors.values.uniq
        end
      end

      test "summarizes all unsummarized comments of an anonymous gist" do
        commenters = [create(:user), create(:user)]
        now = Time.now
        future = now + 1
        Timecop.freeze(future) do
          commenters.each do |user|
            @anonymous_gist.comments.create(body: "Hi", user: user)
          end
        end
        Timecop.freeze(now) do
          summary = NotificationSummary.new(
            list: @anonymous_gist.notifications_list,
            thread: @anonymous_gist)
          refute summary.items.any?

          summary.summarize(@anonymous_gist.comments.last)

          # 1 parent gist and 2 comments.
          assert_equal 3, summary.items.size

          assert_equal @anonymous_gist.title, summary.title
          assert_empty summary.creator_id
          expected_commenters = commenters.map(&:login)
          expected_commenters << "" # the anonymous author of the gist
          assert_same_elements expected_commenters, summary.authors.values.uniq
        end
      end
    end

    context "MemberFeatureRequest::Notification" do
      test "summarizes all member feature request notification" do
        admin = create(:user)
        org = create(:organization, :with_profile, profile_name: "Growth Org Inc.")
        org.add_admin(admin)
        feature = MemberFeatureRequest::Feature::ProtectedBranches
        member_feature_request_notification = create(:member_feature_request_notification,
          entity: org,
          user: admin,
          feature: feature.to_s,
          feature_request_count: 5
        )

        summary = NotificationSummary.new(
          list: member_feature_request_notification.notifications_list,
          thread: member_feature_request_notification.notifications_thread
        )

        summary.summarize(member_feature_request_notification)

        assert_equal "[Growth Org Inc.] You have 5 new requests from members for protected branches", summary.title
        assert_equal 1, summary.items.size
      end

      test "groups same notification by feature" do
        admin = create(:user)
        org = create(:organization, :with_profile, profile_name: "Growth Org Inc.")
        org.add_admin(admin)
        feature = MemberFeatureRequest::Feature::CopilotForBusiness
        member_feature_request_notification = create(:member_feature_request_notification,
          entity: org,
          user: admin,
          feature: feature.to_s,
          feature_request_count: 1
        )

        summary = NotificationSummary.new(
          list: member_feature_request_notification.notifications_list,
          thread: member_feature_request_notification.notifications_thread
        )

        summary.summarize(member_feature_request_notification)
        assert_equal "[Growth Org Inc.] You have 1 new request from members for #{Copilot.business_product_name}", summary.title

        member_feature_request_notification.update(feature_request_count: 10)

        summary.summarize(member_feature_request_notification.reload)
        assert_equal "[Growth Org Inc.] You have 10 new requests from members for #{Copilot.business_product_name}", summary.title

        assert_equal 1, summary.items.size
      end

      test "does not group if notifications have different feature" do
        admin = create(:user)
        org = create(:organization, :with_profile, profile_name: "Growth Org Inc.")
        org.add_admin(admin)

        copilot_feature = MemberFeatureRequest::Feature::CopilotForBusiness
        copilot_member_feature_request_notification = create(:member_feature_request_notification,
          entity: org,
          user: admin,
          feature: copilot_feature.to_s,
          feature_request_count: 1
        )

        copilot_summary = NotificationSummary.new(
          list: copilot_member_feature_request_notification.notifications_list,
          thread: copilot_member_feature_request_notification.notifications_thread
        )

        draft_pr_feature = MemberFeatureRequest::Feature::DraftPullRequests
        draft_pr_member_feature_request_notification = create(:member_feature_request_notification,
          entity: org,
          user: admin,
          feature: draft_pr_feature.to_s,
          feature_request_count: 2
        )

        draft_pr_summary = NotificationSummary.new(
          list: draft_pr_member_feature_request_notification.notifications_list,
          thread: draft_pr_member_feature_request_notification.notifications_thread
        )

        assert_difference "NotificationSummary.count", 2 do
          copilot_summary.summarize!(copilot_member_feature_request_notification)
          draft_pr_summary.summarize!(draft_pr_member_feature_request_notification)
        end

        assert_equal 1, copilot_summary.items.size
        assert_equal 1, draft_pr_summary.items.size
      end
    end

    context "check suite thread summary" do
      test "sets check suite properties at the top level" do
        github_app = create(:integration, name: "Some App")
        check_suite = create(:check_suite, :success, name: "Tests", github_app: github_app)
        event_notification = CheckSuiteEventNotification.new(check_suite)
        summary = NotificationSummary.new(list: check_suite.repository, thread: check_suite)

        summary.summarize(event_notification)

        branch_name = check_suite.head_branch
        assert_equal summary.title, "Tests workflow run succeeded for #{branch_name} branch"
        assert_equal summary.authors.keys, [check_suite.creator_id.to_s]
        assert_equal summary.number, check_suite.id
        assert_equal summary.check_suite_conclusion, check_suite.conclusion
      end

      test "adds attempt to summary title when feature flag is on" do
        GitHub.stubs(:actions_enabled?).returns(true)

        make_trusted_oauth_apps_owner
        check_suite = create(:check_suite_for_actions_app, :success, name: "Tests", repository: @repo)
        check_suite.workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
        check_suite.reload

        event_notification = CheckSuiteEventNotification.new(check_suite)
        summary = NotificationSummary.new(list: check_suite.repository, thread: check_suite)

        summary.summarize(event_notification)

        branch_name = check_suite.head_branch
        assert_equal summary.title, "Tests workflow run, Attempt #2 succeeded for #{branch_name} branch"
      end

      test "does not attempt to summary title when there is only one attempt" do
        GitHub.stubs(:actions_enabled?).returns(true)

        make_trusted_oauth_apps_owner
        check_suite = create(:check_suite_for_actions_app, :success, name: "Tests", repository: @repo)

        event_notification = CheckSuiteEventNotification.new(check_suite)
        summary = NotificationSummary.new(list: check_suite.repository, thread: check_suite)

        summary.summarize(event_notification)

        branch_name = check_suite.head_branch
        assert_equal summary.title, "Tests workflow run succeeded for #{branch_name} branch"
      end

      test "uses the workflow_run.name over check_suite.name when set explicitly" do
        GitHub.stubs(:actions_enabled?).returns(true)

        make_trusted_oauth_apps_owner
        check_suite = create(:check_suite_for_actions_app, :success, name: "Tests", repository: @repo)
        check_suite.workflow_run.update(name: "My custom name", explicit_name: true)

        event_notification = CheckSuiteEventNotification.new(check_suite)
        summary = NotificationSummary.new(list: check_suite.repository, thread: check_suite)

        summary.summarize(event_notification)

        branch_name = check_suite.head_branch
        assert_equal summary.title, "My custom name workflow run succeeded for #{branch_name} branch"
      end
    end
  end

  context "workflow run thread summary" do
    test "sets workflow run properties at the top level" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      check_suite = create(:check_suite_for_actions_app, :failure, repository: @repo)
      workflow_run = check_suite.workflow_run
      event_notification = WorkflowRunApprovalNotification.new(workflow_run)
      summary = NotificationSummary.new(list: workflow_run.repository, thread: workflow_run)

      summary.summarize(event_notification)

      assert_equal summary.title, "#{workflow_run.creator.display_login} requested your review to deploy to an environment"
      assert_equal summary.authors.keys, [workflow_run.creator_id.to_s]
      assert_equal summary.number, workflow_run.id
    end
  end

  context "PullRequestReview" do
    test "summarizes with the review's submitted_at" do
      reviewer = create(:user)
      time = 10.minutes.ago
      pull = travel_to(time) { create(:pull_request, :disable_disk_access) }
      review = travel_to(time) do
        create(:pull_request_review, pull_request: pull, user: reviewer, body: "Review body")
      end

      assert review.comment!

      summary = NotificationSummary.new list: pull.repository, thread: pull.issue
      summary.summarize(review)

      refute_equal review.created_at.to_i, summary.items.values.last[:created_at]
      assert_equal review.submitted_at.to_i, summary.items.values.last[:created_at]
      assert_same_elements [pull.issue.user.login, reviewer.login], summary.authors.values.uniq
      assert_equal "@#{reviewer} commented on this pull request.", summary.items.values.last[:body]
    end
  end

  context "DiscussionEvent::Notification" do
    test "summarizes discussion event" do
      event = create(:discussion_event, :closed)
      discussion = event.discussion
      repository = event.repository

      event_notification = DiscussionEvent::Notification.new(event: event)
      summary = NotificationSummary.new(list: repository, thread: discussion)
      summary.summarize(event_notification)

      assert_equal discussion.title, summary.title
      assert_same_elements [discussion.user.login], summary.authors.values.uniq
      assert_equal discussion.number, summary.number
    end
  end

  context "memex status update thread summary" do
    test "summarizes memex status update event" do
      admin = create(:user)
      organization = create(:organization, admin: admin)
      member = create(:verified_user).tap { |u| organization.add_member(u) }
      memex_project = create(:memex_project, owner: organization)
      memex_project_status = create(:memex_project_status, memex_project: memex_project)
      summary = NotificationSummary.new(list: organization, thread: memex_project_status)

      summary.summarize(memex_project_status)

      assert_equal summary.title, memex_project_status.memex_project.title
      assert_equal summary.number, memex_project_status.memex_project.number
      assert_equal summary.creator_id, memex_project_status.creator_id
      assert_equal summary.authors.keys, [memex_project_status.creator_id.to_s]

      item_key = "MemexProjectStatus:#{memex_project_status.id}"
      item = summary.items[item_key]
      assert_equal item[:permalink], memex_project_status.permalink
    end
  end

  context "#summarize_repository_invitation" do
    test "sets the item" do
      inviter = create(:user)
      invitation = create(:repository_invitation, repository: @repo, invitee: @user, inviter: inviter)
      summary = NotificationSummary.new(list: @repo, thread: @repo)
      summary.summarize_repository_invitation(invitation)
      assert_equal "Invitation to join #{@repo.full_name} from #{inviter.login}", summary.title
      assert_equal inviter.id, summary.items.values.first[:user_id]
    end
  end

  context "#to_summary_hash" do
    test "sets the list type to 'Repository' for an issue" do
      summary = NotificationSummary.new list: @repo, thread: @issue
      assert_equal "Repository", summary.to_summary_hash[:list][:type]
    end

    test "sets the list type to 'Team' for a discussion post" do
      summary = NotificationSummary.new list: @discussion_post.team, thread: @discussion_post
      assert_equal "Team", summary.to_summary_hash[:list][:type]
    end

    test "sets the list type to 'User' for a gist" do
      [@anonymous_gist, @gist].each do |gist|
        summary = NotificationSummary.new list: gist.notifications_list, thread: gist
        assert_equal "User", summary.to_summary_hash[:list][:type]
      end
    end
  end

  context "#list" do
    test "returns a repository when the thread is for an issue" do
      summary = NotificationSummary.new list: @repo, thread: @issue
      assert_equal @repo, summary.list
    end

    test "returns a team when the thread is for a discussion post" do
      summary = NotificationSummary.new list: @discussion_post.team, thread: @discussion_post
      assert_equal @discussion_post.team, summary.list
    end

    test "returns the author when the thread is for a gist" do
      summary = NotificationSummary.new list: @gist.notifications_list, thread: @gist
      assert_equal @gist.user, summary.list
    end

    test "returns the User.ghost when the thread is for an anonymous gist" do
      summary = NotificationSummary.new list: @anonymous_gist.notifications_list, thread: @anonymous_gist
      assert_equal User.ghost, summary.list
    end
  end

  context "#list_owner_id" do
    test "for Repository list type" do
      summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue)

      assert_equal @user.id, summary.list_owner_id
    end

    test "for Team list type" do
      team = @discussion_post.team
      summary = NotificationSummary.fetch_and_update!(team, @discussion_post, @discussion_post_comment)

      assert_equal team.organization_id, summary.list_owner_id
    end

    test "for User list type" do
      gist_comment = create(:gist_comment, gist: @gist)
      summary = NotificationSummary.fetch_and_update!(@user, @gist, @gist_comment)

      assert_equal @user.id, summary.list_owner_id
    end

    test "for Organization list type" do
      org = create(:organization)
      gist = GistHelpers.generate(user: org, created_at: 1.month.ago, contents: [{ name: "gist_file_one.txt", value: "random content" }])
      gist_comment = create(:gist_comment, gist: gist)
      summary = NotificationSummary.fetch_and_update!(org, gist, gist_comment)

      assert_equal org.id, summary.list_owner_id
    end
  end

  context "#thread_author_id" do
    test "for Issue thread" do
      summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue)

      assert_equal @user.id, summary.thread_author_id
    end

    test "for Issue thread with issue comment" do
      another_user = create(:user)
      issue_comment = create(:issue_comment, issue: @issue, user: another_user)
      summary = NotificationSummary.fetch_and_update!(@repo, @issue, issue_comment)

      assert_equal @user.id, summary.thread_author_id
    end

    Newsies::Thread::POSSIBLE_THREAD_TYPES.each do |klass|
      test "assert #{klass} responds to notifications_author" do
        assert klass.new(klass == Commit ? @repo : {}).respond_to?(:notifications_author)
      end
    end
  end

  test "assigning thread updates thread and thread_key" do
    summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue)
    original_thread_key = summary.thread_key
    summary.thread = @issue2
    assert_equal @issue2, summary.thread
    assert_equal Newsies::Thread.to_key(@issue2), summary.thread_key
  end

  test "assigning thread unmemoizes newsies_thread" do
    summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue)
    summary.newsies_thread # memoize newsies thread
    summary.thread = @issue2
    assert_equal @issue2.id.to_s, summary.newsies_thread.id.to_s
  end

  test "assigning thread_key unmemoizes thread and newsies_thread" do
    summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue)
    summary.newsies_thread # memoize newsies thread
    summary.thread # memoize thread
    summary.thread_key = Newsies::Thread.to_key(@issue2)
    assert_equal @issue2.id.to_s, summary.thread.id.to_s
    assert_equal @issue2.id.to_s, summary.newsies_thread.id.to_s
  end

  test "assigning thread to nil" do
    summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue)
    summary.newsies_thread # memoize newsies thread
    summary.thread # memoize thread
    summary.thread = nil
    assert_nil summary.thread
    assert_nil summary.thread_key
    assert_raises Newsies::Object::InvalidKey do
      summary.newsies_thread
    end
  end

  test "#flipper_id works like a list" do
    comment = create(:issue_comment, repository: @repo, issue: @issue)
    summary = NotificationSummary.fetch_and_update!(@repo, @issue, comment)

    GitHub.flipper[:notification_summary_test_actor].enable(@repo)
    assert GitHub.flipper[:notification_summary_test_actor].enabled?(summary)

    GitHub.flipper[:notification_summary_test_actor].disable(@repo)
    refute GitHub.flipper[:notification_summary_test_actor].enabled?(summary)
  end
end
