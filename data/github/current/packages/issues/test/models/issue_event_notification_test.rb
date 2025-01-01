# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueEventNotificationTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    make_trusted_oauth_apps_owner
    create(:merge_queue_integration)

    @user = create(:user, :verified, login: "johndoe")
    @staff_member = create(:staff_admin_user, :verified, login: "staffer", email: "staffer@example.com")
    @ari = create(:user, :verified, login: "ari", plan: "micro")
    @owner = create(:verified_user)

    @repo   = create(:private_repository, owner: @ari, from_example: :pull_request_fork)
    @repo.add_member @user, action: :write
    @repo.add_member @staff_member, action: :write

    @issue = create(:issue, :subscribed_author, title: "bug", body: "things are broke", user: @user, repository: @repo)

    @pull =
      create(:pull_request,
        :with_mergeable_head,
        repository: @repo,
        base_repository: @repo,
        base_user: @ari,
        base_ref: "master",
        head_repository: @repo,
        head_user: @ari,
        head_ref: "topic",
        issue: @issue,
        user: @staff_member,
      )
    @issue.pull_request = @pull
    @issue.save!

    @org = create :organization, login: "acme", admin: @user
    @team = create(:team, organization: @org, name: "team_dog", privacy: :closed)
    @org_repo = create(:repository, owner: @org, from_example: :pull_request_source)
    @org_repo.add_member @ari, action: :write
    @org_repo.add_member @user, action: :write
    @org_repo.add_member @owner, action: :write
    @team.add_member @ari
    @team.add_repository(@org_repo, :push)

    @org_issue = create(:issue, user: @user, repository: @org_repo)
    @org_pull =
      create(:pull_request,
        repository: @org_repo,
        base_repository: @org_repo,
        base_user: @org_repo.owner,
        base_ref: "master",
        head_repository: @org_repo,
        head_user: @org_repo.owner,
        head_ref: "master-forward-2",
        issue: @org_issue,
        user: @user,
      )
    @org_issue.pull_request = @org_pull

    example_repo_snapshot
  end

  setup do
    ActionMailer::Base.deliveries.clear

    GitHub.flipper[:merge_queue].enable(@repo) #enable Merge Queue to test merge queue notifications
    GitHub.flipper[:notifyd_issue_watch_activity_notify].disable
    GitHub.flipper[:notifyd_enable_issues_explicit_auto_subscriptions].disable

    example_repo_restore
  end

  test "wraps an IssueEvent" do
    assert @issue.close(@user)
    event = @issue.events.closes.last
    cn = IssueEventNotification.new(event)
    assert_equal "Closed #1.", cn.body
  end

  test "generates a message-id" do
    issue = create(:issue, title: "bug", body: "things are broke")
    repo = issue.repository
    repo.add_member @user
    example_repo :archive, repo

    assert issue.close(@user)
    event = issue.events.closes.last
    assert_equal "<#{repo.name_with_display_owner}/issue/#{issue.number}/issue_event/#{event.id}@#{GitHub.host_name}>",
      IssueEventNotification.new(event).message_id
  end

  test "find_by_id returns a IssueEventNotification wrapping the IssueEvent" do
    @issue.close(@user)
    event = @issue.events.closes.last
    cn = IssueEventNotification.find_by_id(event.id)
    assert_equal IssueEventNotification, cn.class
    assert_equal event, cn.issue_event
    assert_equal @issue, cn.issue
  end

  test "sends notification and escapes html" do
    @pull.issue.title = "<br><br><h1>HI HTML TITLE HERE</h1><br><br>"
    @pull.save!

    @pull_user = create(:verified_user)

    @pull.repository.add_member @pull_user

    perform_notification_jobs do
      @pull.request_review_from(reviewers: [@pull_user], actor: @pull.user)
    end

    deliveries = ActionMailer::Base.deliveries
    mail = deliveries.last

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_match "@#{@user.display_login}", text_part(mail)
    assert_match @pull_user.display_login, mail.header["Cc"].to_s
    assert_match "requested your review on:", text_part(mail)
    assert_match "#{@pull.repository.name_with_display_owner}", text_part(mail)
    assert_match @user.display_login, mail.header["From"].to_s
    refute_match "<br><br><h1>HI HTML TITLE HERE</h1><br><br>", html_part(mail)
    assert_match "&lt;br&gt;&lt;br&gt;&lt;h1&gt;HI HTML TITLE HERE&lt;/h1&gt;&lt;br&gt;&lt;br&gt;", html_part(mail)
  end

  test "sends notification for assigning the issue" do
    GitHub.context.push(actor_id: @staff_member.id)
    @issues_user = create(:verified_user)
    @issue.repository.add_member @issues_user

    perform_notification_jobs do
      @issue.assignee = @issues_user
      @issue.save!
    end

    deliveries = ActionMailer::Base.deliveries
    mail = deliveries.last

    assert_match @issues_user.display_login, mail.header["Cc"].to_s
    assert_match "Assigned", text_part(mail)
    assert_match @staff_member.display_login, mail.header["From"].to_s
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "doesn't send notification for assigning the issue if delivery via Notifyd is enabled" do
    issue = create(:issue, :subscribed_author, title: "bug", body: "things are broke", user: @user, repository: @repo)
    user = create(:verified_user)
    GitHub.flipper[:notifyd_issue_watch_activity_notify].enable(user)
    GitHub.flipper[:notifyd_enable_issues_explicit_auto_subscriptions].enable(@user)
    issue.repository.add_member user

    perform_notification_jobs do
      issue.assignee = user
      issue.save!
    end

    refute ActionMailer::Base.deliveries.last
  end

  test "doesn't send notification for self-assigning the issue" do
    @issues_user = create(:verified_user)
    GitHub.context.push(actor_id: @issues_user.id)
    @issue.repository.add_member @issues_user
    @issue.assignee = @issues_user
    @issue.save

    assert_nil ActionMailer::Base.deliveries.last
  end

  test "sends notification for requesting review the pull" do
    @pull_user = create(:verified_user)

    @pull.repository.add_member @pull_user

    perform_notification_jobs do
      @pull.request_review_from(reviewers: [@pull_user], actor: @pull.user)
    end

    deliveries = ActionMailer::Base.deliveries
    mail = deliveries.last

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_match "@#{@user.display_login}", text_part(mail)
    assert_match @pull_user.display_login, mail.header["Cc"].to_s
    assert_match "requested your review on:", text_part(mail)
    assert_match "#{@pull.repository.name_with_display_owner}", text_part(mail)
    assert_match @user.display_login, mail.header["From"].to_s
  end

  test "sends notification for requesting review from a team on the pull" do
    perform_notification_jobs do
      @org_pull.request_review_from(reviewers: [@team], actor: @user)
    end

    event = @org_pull.events.last
    deliveries = ActionMailer::Base.deliveries
    mail = deliveries.last

    assert event.review_requested?

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_match "@#{@user.display_login}", text_part(mail)
    assert_match @ari.display_login, mail.header["Cc"].to_s
    assert_match "requested review from @#{@team} on:", text_part(mail)
    assert_match "#{@org_pull.repository.name_with_display_owner}", text_part(mail)
    assert_match @user.display_login, mail.header["From"].to_s
  end

  test "does not sends notification to the PR author if they are on the requested team" do
    @team.add_member @org_pull.user

    ActionMailer::Base.deliveries.clear

    perform_notification_jobs do
      @org_pull.request_review_from(reviewers: [@team], actor: @user)
    end
    event = @org_pull.events.last
    deliveries = ActionMailer::Base.deliveries
    mail = deliveries.last

    assert event.review_requested?

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_match "@#{@user.display_login}", text_part(mail)
    assert_match @ari.display_login, mail.header["Cc"].to_s
    assert_match "requested review from @#{@team} on:", text_part(mail)
    assert_match "#{@org_pull.repository.name_with_display_owner}", text_part(mail)
    assert_match @user.display_login, mail.header["From"].to_s
  end

  test "does not send notification if the person requesting review is also on a team" do
    @team.add_member @owner

    ActionMailer::Base.deliveries.clear
    GitHub.context.push(actor_id: @ari.id)

    perform_notification_jobs do
      @org_pull.request_review_from(reviewers: [@team], actor: @ari)
    end

    event = @org_pull.events.last
    deliveries = ActionMailer::Base.deliveries
    mail = deliveries.last

    assert event.review_requested?

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_match "@#{@ari.display_login}", text_part(mail)
    assert_match @owner.display_login, mail.header["Cc"].to_s
    assert_match "requested review from @#{@team} on:", text_part(mail)
    assert_match "#{@org_pull.repository.name_with_display_owner}", text_part(mail)
    assert_match @ari.display_login, mail.header["From"].to_s
  end

  test "doesn't send notification for self-requesting review" do
    @pull_user = create(:verified_user)
    GitHub.context.push(actor_id: @pull_user.id)
    @pull.repository.add_member @pull_user
    @pull.request_review_from(reviewers: [@pull_user], actor: @pull.user)

    assert_nil ActionMailer::Base.deliveries.last
  end

  test "sends notification for requesting review via codeownership" do
    @pull_user = create(:verified_user)

    @pull.repository.add_member @pull_user

    perform_notification_jobs do
      base_ref = @pull.head_repository.heads.find("master")
      base_ref.append_commit({ message: "codeowners", committer: @pull.repository.owner }, @pull.repository.owner) do |files|
        files.add("CODEOWNERS", <<~CODEOWNERS)
          *  @#{@pull_user}
        CODEOWNERS
      end
      @pull.request_review_from_codeowners(@pull.user, should_save: true)
    end

    deliveries = ActionMailer::Base.deliveries
    mail = deliveries.last

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_match "@#{@user.display_login}", text_part(mail)
    assert_match @pull_user.display_login, mail.header["Cc"].to_s
    assert_match "requested your review on:", text_part(mail)
    assert_match "#{@pull.repository.name_with_display_owner}", text_part(mail)
    assert_match "as a code owner", text_part(mail)
    assert_match @user.display_login, mail.header["From"].to_s
  end

  test "sends notification for the closing of the issue" do
    perform_notification_jobs do
      assert @issue.close(@user)
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "Closed", text_part(mail)
  end

  test "doesn't send notification for the closing of the issue if delivery via Notifyd is enabled" do
    issue = create(:issue, :subscribed_author, title: "bug", body: "things are broke", user: @user, repository: @repo)
    GitHub.flipper[:notifyd_issue_watch_activity_notify].enable(@user)

    perform_notification_jobs do
      assert issue.close(@user)
    end
    refute ActionMailer::Base.deliveries.last
  end

  test "sends notification for the closing a pull request" do
    @pull.subscribe @staff_member, "manual"

    perform_notification_jobs do
      assert @pull.close(@pull.user)
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "Closed", html_part(mail)
  end

  test "sends notification when a pull request is merged" do
    @pull.subscribe @staff_member, "manual"
    @pull.update_attribute :merged_at, Time.now

    perform_notification_jobs do
      @pull.issue.events.create!(event: "merged", actor: @pull.user, commit_id: "a" * 40)
      assert @pull.close(@pull.user)
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "Merged", html_part(mail)
    assert_match "master", html_part(mail), "should include the branch name in merge notifications"
  end

  test "sends notification for a commit closing an issue with reason included" do
    issue = create(:issue, title: "bug", body: "things are broke")
    repo = issue.repository
    repo.add_member @user
    example_repo :archive, repo

    issue.subscribe @staff_member, "manual"
    commit_id = "859b2de82a9eaceb8fcd4f9b66ccb1c98edca4ca"

    perform_notification_jobs do
      assert issue.close(@user, attributes: { commit: { id: commit_id } })
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "Closed ##{issue.number} as completed via #{commit_id}.", text_part(mail)
    assert_match "#{GitHub.host_name}/#{issue.repository.name_with_display_owner}/commit/#{commit_id}", html_part(mail)
  end

  test "sends notification for a commit closing an issue in another repo" do
    @other_repo = create(:repository)
    @issue.subscribe @staff_member, "manual"
    commit_id = Sham.sha
    perform_notification_jobs do
      assert @issue.close(@user, attributes: { commit: { id: commit_id, repository: @other_repo } })
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "Closed ##{@issue.number} via #{@other_repo.name_with_display_owner}@#{commit_id}.", text_part(mail)
    assert_match "#{GitHub.host_name}/#{@other_repo.name_with_display_owner}/commit/#{commit_id}", html_part(mail)
  end

  test "sends notification for a commit closing an issue in another repo when the commit repo can't be seen by user" do
    @other_repo = create(:private_repository)
    @issue.subscribe @staff_member, "manual"
    commit_id = Sham.sha
    perform_notification_jobs do
      assert @issue.close(@user, attributes: { commit: { id: commit_id, repository: @other_repo } })
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "Closed ##{@issue.number} via #{commit_id}.", text_part(mail)
    refute_match %r{#{GitHub.host_name}/#{@other_repo.name_with_display_owner}/}, html_part(mail)
  end

  test "sends notification for a PR closing an issue" do
    @issue.subscribe @staff_member, "manual"
    pr = create(:issue, repository: @issue.repository)  # making a true PR is a pain, this is good enough
    perform_notification_jobs do
      assert @issue.close(@user, attributes: { pr: pr.id })
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "Closed ##{@issue.number} via ##{pr.number}.", text_part(mail)
    assert_match "#{GitHub.host_name}/#{@issue.repository.name_with_display_owner}/issues/#{pr.number}", html_part(mail)
  end

  test "sends notification for a PR closing an issue in another repo" do
    @other_repo = create(:repository)
    @issue.subscribe @staff_member, "manual"
    pr = create(:issue, repository: @other_repo)  # making a true PR is a pain, this is good enough
    perform_notification_jobs do
      assert @issue.close(@user, attributes: { pr: pr.id })
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "Closed ##{@issue.number} via #{@other_repo.name_with_display_owner}##{pr.number}.", text_part(mail)
    assert_match "#{GitHub.host_name}/#{@other_repo.name_with_display_owner}/issues/#{pr.number}", html_part(mail)
  end

  test "sends notification for a PR closing an issue in another repo when the PR repo can't be seen by user" do
    @other_repo = create(:private_repository)
    @issue.subscribe @staff_member, "manual"
    pr = create(:issue, repository: @other_repo)  # making a true PR is a pain, this is good enough
    perform_notification_jobs do
      assert @issue.close(@user, attributes: { pr: pr.id })
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "Closed ##{@issue.number}.", text_part(mail)
    refute_match %r{#{GitHub.host_name}/#{@other_repo.name_with_display_owner}/}, html_part(mail)
  end

  test "sends notification for a reopen of an issue" do
    Spokesd.enable_spokesd

    perform_notification_jobs do
      assert @issue.close(@user)
      assert @issue.open(@user)
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "Reopened", html_part(mail)
  end

  test "doesn't send notification for a reopen of an issue if delivery via Notifyd is enabled" do
    issue = create(:issue, :subscribed_author, title: "bug", body: "things are broke", user: @user, repository: @repo)
    GitHub.flipper[:notifyd_issue_watch_activity_notify].enable(@user)

    perform_notification_jobs do
      assert issue.close(@user)
      assert issue.open(@user)
    end
    refute ActionMailer::Base.deliveries.last
  end

  test "sends close notifications to gen pop" do
    @issue.user.update! gh_role: nil
    @issue.repository.add_member @user
    perform_notification_jobs do
      assert @issue.close(@user)
    end
    mail = ActionMailer::Base.deliveries.last
    refute_nil mail
  end

  test "links to the issue in question" do
    @pull.subscribe @staff_member, "manual"
    perform_notification_jobs do
      assert @pull.close(@pull.user)
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match %r|Closed <a[^>]*href=\"https://#{GitHub.host_name}/#{@pull.repository.nwo}/pull/1\"|, html_part(mail)
  end

  test "sends notification when issue is converted to discussion" do
    repo = create(:repository, has_discussions: true)

    issue = create(:issue, repository: repo)
    issue.subscribe @staff_member, "manual"
    category = create(:discussion_category, repository: repo)
    discussion = Discussion.from_issue(issue, category: category)
    discussion.save!
    converter = IssueToDiscussionConverter.new(issue, actor: repo.owner)

    perform_notification_jobs do
      converter.finish_conversion
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "@#{repo.owner} converted this issue into discussion ##{discussion.number}.", text_part(mail)
    assert_match "#{GitHub.host_name}/#{repo.name_with_display_owner}/discussions/#{discussion.number}", html_part(mail)
  end

  test "doesn't send notification when issue is converted to discussion if delivery via Notifyd is enabled" do
    repo = create(:repository, has_discussions: true)
    GitHub.flipper[:notifyd_issue_watch_activity_notify].enable(repo.owner)
    GitHub.flipper[:notifyd_issue_watch_activity_notify].enable(@staff_member)
    GitHub.flipper[:notifyd_enable_issues_explicit_auto_subscriptions].enable(repo.owner)

    issue = create(:issue, repository: repo)
    issue.subscribe @staff_member, "manual"
    category = create(:discussion_category, repository: repo)
    discussion = Discussion.from_issue(issue, category: category)
    discussion.save!
    converter = IssueToDiscussionConverter.new(issue, actor: repo.owner)

    perform_notification_jobs do
      converter.finish_conversion
    end
    refute ActionMailer::Base.deliveries.last
  end

  context "merge queue issue_events" do
    if GitHub.merge_queues_enabled? #Merge Queue is not available in GitHub Enterprise
      test "sends notifications (email and web) when a PR is added to the merge queue by someone other than the author" do
        queue = create(:merge_queue, repository: @repo, branch: @repo.default_branch)
        pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @staff_member)
        enable_notifications_for_user(@staff_member)

        perform_notification_jobs do
          queue.enqueue!(pull_request: pull, enqueuer: @user)
        end

        mail = ActionMailer::Base.deliveries.last
        assert_match "#{pull.number} was added to the [merge queue](#{GitHub.url + queue.async_path_uri.sync.to_s})", text_part(mail)
        assert_delivered_web_notification(@staff_member, IssueEventNotification.new(pull.issue.events.last), "state_change")
      end

      test "does not sends notifications (email and web) when a PR is added to the merge queue by author and `notify_own_email` is false" do
        queue = create(:merge_queue, repository: @repo, branch: @repo.default_branch)
        pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
        enable_notifications_for_user(@user)
        GitHub.newsies.get_and_update_settings(@user) do |u|
          u.notify_own_via_email = false
        end

        perform_notification_jobs do
          queue.enqueue!(pull_request: pull, enqueuer: @user)
        end

        refute_delivered_web_notification(@user, IssueEventNotification.new(pull.issue.events.last))
        refute_delivered_email_notification(@user, IssueEventNotification.new(pull.issue.events.last))
      end

      test "sends notifications email when a PR is added to the merge queue by author and `notify_own_email` is true" do
        queue = create(:merge_queue, repository: @repo, branch: @repo.default_branch)
        pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
        enable_notifications_for_user(@user)
        GitHub.newsies.get_and_update_settings(@user) do |u|
          u.notify_own_via_email = true
        end

        perform_notification_jobs do
          queue.enqueue!(pull_request: pull, enqueuer: @user)
        end

        mail = ActionMailer::Base.deliveries.last
        assert_match "#{pull.number} was added to the [merge queue](#{GitHub.url + queue.async_path_uri.sync.to_s})", text_part(mail)
      end

      test "does not sends notifications (email and web) when a PR is removed from the merge queue by author and `notify_own_email` is false" do
        queue = create(:merge_queue, repository: @repo, branch: @repo.default_branch)
        pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
        enable_notifications_for_user(@user)
        GitHub.newsies.get_and_update_settings(@user) do |u|
          u.notify_own_via_email = false
        end

        perform_notification_jobs do
          queue.enqueue!(pull_request: pull, enqueuer: @user)
          queue.dequeue(pull_request: pull, dequeuer: @user)
        end

        refute_delivered_web_notification(@user, IssueEventNotification.new(pull.issue.events.last))
        refute_delivered_email_notification(@user, IssueEventNotification.new(pull.issue.events.last))
      end

      test "sends notifications email when a PR is removed to the merge queue manually by the author and `notify_own_email` is true" do
        queue = create(:merge_queue, repository: @repo, branch: @repo.default_branch)
        pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
        enable_notifications_for_user(@user)
        GitHub.newsies.get_and_update_settings(@user) do |u|
          u.notify_own_via_email = true
        end

        perform_notification_jobs(more: [MergeQueueEntryRemovedJob]) do
          queue.enqueue!(pull_request: pull, enqueuer: @user)
          queue.dequeue(pull_request: pull, dequeuer: @user)
        end

        mail = ActionMailer::Base.deliveries.last
        assert_match "##{pull.number} was manually removed from the [merge queue](#{GitHub.url + queue.async_path_uri.sync.to_s}) by #{@user.display_login}.", text_part(mail)
      end

      test "sends notifications (web and email) to author and enqueuer when a PR is removed to the merge queue manually by someone else that the author" do
        queue = create(:merge_queue, repository: @repo, branch: @repo.default_branch)
        pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @staff_member)
        bot = create(:integration).bot
        enable_notifications_for_user(@staff_member)
        enable_notifications_for_user(@user)

        perform_notification_jobs(more: [MergeQueueEntryRemovedJob]) do
          queue.enqueue!(pull_request: pull, enqueuer: @user)
          queue.dequeue(pull_request: pull, dequeuer: bot)
        end
        mail = ActionMailer::Base.deliveries.last
        assert_match "##{pull.number} was manually removed from the [merge queue](#{GitHub.url + queue.async_path_uri.sync.to_s}) by #{bot.display_login}.", text_part(mail)
        assert_delivered_web_notification(@staff_member, IssueEventNotification.new(pull.issue.events.last), "state_change")
        assert_delivered_web_notification(@user, IssueEventNotification.new(pull.issue.events.last), "state_change")
      end

      test "sends notifications (web and email) when a PR is removed to the merge queue due to failing ci" do
        queue = create(:merge_queue, repository: @repo, branch: @repo.default_branch)
        enable_notifications_for_user(@staff_member)
        pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @staff_member)
        entry = queue.enqueue!(pull_request: pull, enqueuer: @user)
        bot = create(:integration).bot

        entry.removal_reason = MergeQueueEntry::REMOVAL_REASONS[:ci_failure]
        entry.removal_commit_oid = SecureRandom.hex(20)
        entry.dequeuer = bot
        perform_notification_jobs(more: [MergeQueueEntryRemovedJob]) do
          entry.destroy!
        end
        assert_delivered_web_notification(@staff_member, IssueEventNotification.new(pull.issue.events.last), "state_change")

        mail = ActionMailer::Base.deliveries.last
        assert_match "##{pull.number} was automatically removed from the [merge queue](#{GitHub.url + queue.async_path_uri.sync.to_s}) due to failed status checks", text_part(mail)
      end

      test "sends notifications (web and email) when a PR is removed to the merge queue due to merge conflict" do
        queue = create(:merge_queue, repository: @repo, branch: @repo.default_branch)
        pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @staff_member)
        enable_notifications_for_user(@staff_member)
        entry = queue.enqueue!(pull_request: pull, enqueuer: @user)
        bot = create(:integration).bot

        entry.removal_reason = MergeQueueEntry::REMOVAL_REASONS[:merge_conflict]
        entry.removal_commit_oid = SecureRandom.hex(20)
        entry.dequeuer = bot
        perform_notification_jobs(more: [MergeQueueEntryRemovedJob]) { entry.destroy! }

        mail = ActionMailer::Base.deliveries.last
        assert_match "##{pull.number} was automatically removed from the [merge queue](#{GitHub.url + queue.async_path_uri.sync.to_s}) due to a conflict with the base branch", text_part(mail)
        assert_delivered_web_notification(@staff_member, IssueEventNotification.new(pull.issue.events.last), "state_change")
      end
    end
  end

  private

  # Returns the text part of the email as a string
  def text_part(mail)
    mail.text_part.body.decoded
  end

  # Returns the html part of the email as a string
  def html_part(mail)
    mail.html_part.body.decoded
  end

  def perform_notification_jobs(more: [], &block)
    only = [
      Newsies::DeliverNotificationsJob,
      SubscribeAndNotifyJob,
      AsyncNewsiesDeliveryJob,
    ] + more
    perform_enqueued_jobs(only:, &block)
  end
end
