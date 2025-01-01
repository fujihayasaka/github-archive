# typed: true
# frozen_string_literal: true

require "test_helper"

class MentionAndSubscribeTest < GitHub::TestCase
  fixtures do
    @owner = create :verified_user, login: "owner"
    @owner.update(plan: "medium")
    @collaborator = create :verified_user, login: "collaborator"

    @visitor = create :verified_user, login: "visitor"
    @interloper = create :verified_user, login: "interloper"
    @private_repo = create(:private_repository, owner: @owner)
    @issue = create(:issue, repository: @private_repo, user: @owner)
    @private_repo.add_member(@collaborator)

    @repo = create(:repository, owner: @owner)
    @reader = create :verified_user, login: "reader"
    @repo.add_member(@collaborator)
    @repo.add_member(@visitor, action: :read)
    @repo.add_member(@reader, action: :read)
  end

  setup do
    deliveries.clear
    GitHub.flipper[:notifyd_issue_watch_activity_notify].disable
  end

  context "Issue Comments" do
    test "includes unauthorized mentions but doesn't subscribe them" do
      comment = create_comment_with_mentions

      assert_same_elements [@visitor, @collaborator], comment.mentioned_users

      # check that explicitly calling subscribe_mentioned does not
      # add the outside user
      comment.subscribe_mentioned
      refute comment.subscribed?(@visitor)
      assert comment.subscribed?(@collaborator)
    end

    test "creates issue event for unauthorized mentions but not for subscribed" do
      comment = create_comment_with_mentions

      # expectation is that if the user is not subscribed then there would be
      # no subscribed event associated with the user
      assert_equal 1, @issue.events.where(event: "subscribed").count
      assert_equal 2, @issue.events.mentions.count
    end

    test "only sends email to authorized mention" do
      comment = create_comment_with_mentions

      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, AsyncNewsiesDeliveryJob]
      assert_performed_with job: Newsies::DeliverNotificationsJob do
        perform_enqueued_jobs(only: only)
      end
      assert_equal 1, deliveries.size
      assert_same_elements [@collaborator.email, "mention@noreply.github.com"], deliveries.first.cc
    end

    test "changing a comment body does not subscribe or send email to unauthorized mention" do
      comment = create_comment_with_mentions
      comment.body = "what do you think? /cc @visitor, @interloper and @collaborator"
      comment.save!

      assert comment.subscribed?(@collaborator)
      refute comment.subscribed?(@visitor)
      refute comment.subscribed?(@interloper)

      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, AsyncNewsiesDeliveryJob]
      assert_performed_with job: Newsies::DeliverNotificationsJob do
        perform_enqueued_jobs(only: only)
      end
      assert_equal 1, deliveries.size
      assert_same_elements [@collaborator.email, "mention@noreply.github.com"], deliveries.first.cc
    end

    test "changing a comment body creates issue event for unauthorized mentions but not for subscribed" do
      assert_performed_with job: SubscribeAndNotifyJob do
        comment = create_comment_with_mentions
        comment.body = "what do you think? /cc @visitor, @interloper and @collaborator"
        comment.save!
      end

      assert_equal 1, @issue.events.where(event: "subscribed").count
      assert_equal 3, @issue.events.mentions.count
    end

    unless GitHub.enterprise?
      test "does not subscribe a mentioned user if the author is spammy" do
        spammy_user = create(:user,
          login: "spammy",
          plan: "medium",
          spammy: true,
        )
        comment = create(:issue_comment,
          repository: @repo,
          issue: @issue,
          user: spammy_user,
          body: "Hey @visitor, lookit this",
        )
        assert_equal 0, @issue.events.mentions.count
      end
    end

    # checking that the IssueEvent for subscribe does not somehow autosubscribe
    # when the user gets added to the repo
    test "adding a user does not backfill subscribed to mentions" do
      comment = create_comment_with_mentions

      @private_repo.add_member(@visitor)
      refute comment.subscribed?(@visitor)

      # unwatch repo so we don't have the general watching notifications
      @collaborator.unwatch_repo(@private_repo)
      @visitor.unwatch_repo(@private_repo)

      # no mention comment
      comment = create(:issue_comment, :wait_for_orchestration, repository: @private_repo, issue: @issue, user: @owner, body: "no mentions")
      refute comment.subscribed?(@visitor)
      assert comment.subscribed?(@collaborator)

      # the newly added user does not get auto subscribed for the old mention
      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, AsyncNewsiesDeliveryJob]
      perform_enqueued_jobs(only: only) do
        comment.deliver_notifications
      end
      assert_equal 1, deliveries.size
      assert_same_elements [@collaborator.email, "mention@noreply.github.com"], deliveries.first.cc
      refute comment.subscribed?(@visitor)

      # mention the user again and they get subscribed as expected
      assert_performed_with job: SubscribeAndNotifyJob do
        deliveries.clear
        # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        comment = perform_enqueued_jobs do
          # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
          create(:issue_comment, repository: @private_repo, issue: @issue, user: @owner, body: "ok @visitor should now be subscribed")
        end

        assert comment.subscribed?(@visitor)
        assert comment.subscribed?(@collaborator)
        assert_equal 2, deliveries.size
      end
    end

    test "subscribes and notifies authorized mentions with deliver_now" do
      GitHub.flipper[:deliver_email_notifications_bg_job].disable
      comment = T.let(nil, T.nilable(IssueComment))

      assert_performed_jobs(2, only: [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]) do
        comment = create(:issue_comment, :wait_for_orchestration, repository: @private_repo, issue: @issue, user: @owner, body: "cc @visitor, @collaborator take a look")
      end

      assert T.must(comment).subscribed?(@collaborator)
      refute T.must(comment).subscribed?(@visitor)

      assert_equal 1, deliveries.size
    end

    test "subscribes and notifies authorized mentions with deliver_later" do
      GitHub.flipper[:deliver_email_notifications_bg_job].enable(true)
      comment = T.let(nil, T.nilable(IssueComment))

      assert_performed_jobs(3, only: [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob, AsyncNewsiesDeliveryJob]) do
        comment = create(:issue_comment, :wait_for_orchestration, repository: @private_repo, issue: @issue, user: @owner, body: "cc @visitor, @collaborator take a look")
      end

      assert T.must(comment).subscribed?(@collaborator)
      refute T.must(comment).subscribed?(@visitor)

      assert_equal 1, deliveries.size
    end
  end

  context "Issues" do
    test "includes unauthorized mentions but doesn't subscribe them" do
      issue = create_issue_with_mentions(repo: @private_repo)
      assert issue.subscribed?(@collaborator)

      assert_same_elements [@visitor, @collaborator], issue.mentioned_users

      # check that explicitly calling subscribe_mentioned does not
      # add the outside user
      issue.subscribe_mentioned
      refute issue.subscribed?(@visitor)
      assert issue.subscribed?(@collaborator)
    end

    test "creates issue event for unauthorized mentions but not for subscribed" do
      issue = create_issue_with_mentions(repo: @private_repo)

      # expectation is that if the user is not subscribed then there would be
      # no subscribed event associated with the user
      assert_equal 1, issue.events.where(event: "subscribed").count
      assert_equal 2, issue.events.mentions.count
    end

    test "only sends email to authorized mention" do
      issue = create_issue_with_mentions(repo: @private_repo)

      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, AsyncNewsiesDeliveryJob]
      assert_performed_with job: Newsies::DeliverNotificationsJob do
        perform_enqueued_jobs(only: only)
      end
      assert_equal 1, deliveries.size
      assert_same_elements [@collaborator.email, "mention@noreply.github.com"], deliveries.first.cc
    end

    test "changing an issue body does not subscribe or send email to unauthorized mention" do
      issue = create_issue_with_mentions(repo: @private_repo)
      issue.body = "what do you think? /cc @visitor, @interloper and @collaborator"
      issue.save!

      assert issue.subscribed?(@collaborator)
      refute issue.subscribed?(@visitor)
      refute issue.subscribed?(@interloper)

      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, AsyncNewsiesDeliveryJob]
      assert_performed_with job: Newsies::DeliverNotificationsJob do
        perform_enqueued_jobs(only: only)
      end
      assert_equal 1, deliveries.size
      assert_same_elements [@collaborator.email, "mention@noreply.github.com"], deliveries.first.cc
    end

    test "changing an issue body creates issue event for unauthorized mentions but not for subscribed" do
      assert_performed_with job: SubscribeAndNotifyJob do
        issue = create_issue_with_mentions(repo: @private_repo)
        issue.body = "what do you think? /cc @visitor, @interloper and @collaborator"
        issue.save!

        assert_equal 1, issue.events.where(event: "subscribed").count
        assert_equal 3, issue.events.mentions.count
      end
    end

    # checking that the IssueEvent for subscribe does not somehow autosubscribe
    # when the user gets added to the repo
    test "adding a user does not backfill subscribed to mentions" do
      issue = create_issue_with_mentions(repo: @private_repo)

      @private_repo.add_member(@visitor)
      refute issue.subscribed?(@visitor)

      # unwatch repo so we don't have the general watching notifications
      @collaborator.unwatch_repo(@private_repo)
      @visitor.unwatch_repo(@private_repo)

      # the newly added user does not get auto subscribed for the old mention
      only = T.let([Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, AsyncNewsiesDeliveryJob], T::Array[Class])
      assert_performed_with job: Newsies::DeliverNotificationsJob do
        perform_enqueued_jobs(only: only)
      end
      assert_equal 1, deliveries.size
      assert_same_elements [@collaborator.email, "mention@noreply.github.com"], deliveries.first.cc
      refute issue.subscribed?(@visitor)

      # mention the user again and they get subscribed as expected
      assert_performed_with job: SubscribeAndNotifyJob do
        # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        issue = perform_enqueued_jobs(except: Newsies::DeliverNotificationsJob) do
          # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
          create(:issue, repository: @private_repo, user: @owner, body: "ok @visitor, @collaborator should now be subscribed")
        end

        assert issue.subscribed?(@visitor)
        assert issue.subscribed?(@collaborator)

        deliveries.clear
        only = [AddToSearchIndexJob, DeliverHookEventJob, Newsies::DeliverNotificationsJob, NotifySubscriptionStatusChangeJob, ProcessEventJob, SubscribeAndNotifyJob, UpdateEventFeedsJob, AsyncNewsiesDeliveryJob]
        perform_enqueued_jobs(only: only)
        assert_equal 2, deliveries.size
      end
    end


    test "subscribes and notifies authorized mentions with deliver_later" do
      GitHub.flipper[:deliver_email_notifications_bg_job].enable(true)

      issue = T.let(nil, T.nilable(Issue))

      assert_performed_jobs(3, only: [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob, AsyncNewsiesDeliveryJob]) do
        issue = create(:issue, repository: @private_repo, user: @owner, body: "cc @visitor, @collaborator take a look")
      end

      assert T.must(issue).subscribed?(@collaborator)
      refute T.must(issue).subscribed?(@visitor)

      assert_equal 1, deliveries.size
    end

    test "subscribes and notifies authorized mentions with deliver_now" do
      GitHub.flipper[:deliver_email_notifications_bg_job].disable

      issue = T.let(nil, T.nilable(Issue))

      assert_performed_jobs(2, only: [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]) do
        issue = create(:issue, repository: @private_repo, user: @owner, body: "cc @visitor, @collaborator take a look")
      end

      assert T.must(issue).subscribed?(@collaborator)
      refute T.must(issue).subscribed?(@visitor)

      assert_equal 1, deliveries.size
    end
  end

  # comment on the private_repo's issue and mention a collaborator and
  # a user that does not have access to the repo
  def create_comment_with_mentions
    body = "what do you think? /cc @visitor and @collaborator"
    comment = T.let(nil, T.nilable(IssueComment))

    assert_performed_with job: SubscribeAndNotifyJob do
      only = [SubscribeAndNotifyJob]
      comment = perform_enqueued_jobs(only: only) do
        create(:issue_comment, :wait_for_orchestration, repository: @private_repo, issue: @issue, user: @owner, body: body)
      end

      # check that the comment only subscribes the collaborator and not the visitor
      refute comment.subscribed?(@visitor)
      assert comment.subscribed?(@collaborator)
    end

    comment
  end

  # create an issue for the given repo that mentions a collaborator and
  # a visitor that does not have access to the repo or issue
  def create_issue_with_mentions(repo:)
    body = "what do you think? /cc @visitor and @collaborator"

    only = [SubscribeAndNotifyJob]
    issue = perform_enqueued_jobs(only: only) do
      create(:issue, repository: repo, user: @owner, body: body)
    end

    # check that the issue only subscribes the collaborator and not the visitor
    assert issue.subscribed?(@collaborator)
    issue
  end

  def deliveries
    ActionMailer::Base.deliveries
  end
end
