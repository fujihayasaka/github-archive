# typed: true
# frozen_string_literal: true

require "test_helper"

class ReviewRequestTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @org = create(:organization, admin: @owner)
    @org.allow_private_repository_forking(actor: @owner)

    @team = create(:team, organization: @org, privacy: :closed)
    @forker = create(:user)
    @rando = create(:user)

    @source = create(:private_repository, owner: @org, name: "source", from_example: :review_comment_fork)
    @source.add_team @team, action: :write
    @source.add_member @forker, action: :write

    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

    @issue = create(:issue, user: @forker, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @forker,
      )
    @issue.pull_request = @pull

    @request = @pull.review_requests.create!(reviewer: @owner)
    @team_request = @pull.review_requests.create!(reviewer: @team)
  end

  test "validates reviewer is a repo collaborator" do
    @request.reviewer = @rando
    refute_predicate @request, :valid?
    assert_includes @request.errors.messages[:reviewer], "must be a collaborator"
  end

  test "does not validate reviewer is a repo collaborator if dismissed" do
    @request.dismiss
    @request.reviewer = @rando
    assert_predicate @request, :valid?
  end

  test "validates reviewer is a not the PR author" do
    @request.reviewer = @forker
    refute_predicate @request, :valid?
    assert_includes @request.errors.messages[:reviewer], "cannot be PR author"
  end

  test "validates cant create two pending requests" do
    request = @pull.review_requests.create(reviewer: @owner)
    refute_predicate request, :valid?
    assert_includes request.errors.messages[:reviewer], "can only have one pending request per pull request"
  end

  test "creating a review request notifies state changes" do
    reviewer = create(:collaborator, login: "assignee-mcgee", repository: @source)

    channel = GitHub::WebSocket::Channels.pull_request_review_state(@pull)
    GitHub::WebSocket.stubs(:notify_repository_channel).returns([])
    GitHub::WebSocket.expects(:notify_repository_channel)
      .with(@pull.repository, channel, has_key(:pull_request_id))
      .once

    @pull.review_requests.create(reviewer: reviewer)
  end

  test "triggers an review_request event on the parent pull when created" do
    reviewer = create(:collaborator, login: "assignee-mcgee", repository: @source)

    assert_difference("@issue.events.count", 1) do
      @pull.review_requests.create!(reviewer: reviewer)
    end

    review_request = @pull.review_requests.last
    request_event = @pull.events.last
    assert_equal "review_requested",  request_event.event
    assert_equal reviewer,    request_event.subject
    assert_equal @pull.user, request_event.actor
    assert_equal review_request.id, request_event.review_request_id
  end

  context ".for" do
    test "finds requests for a single user" do
      assert_same_elements [@request], ReviewRequest.for(@owner)
    end

    test "finds requests for a single team" do
      assert_same_elements [@team_request], ReviewRequest.for(@team)
    end

    test "finds requests for a mixed list" do
      assert_same_elements [@request, @team_request], ReviewRequest.for(@owner, @team)
      assert_same_elements [@request, @team_request], ReviewRequest.for([@owner, @team])
    end
  end

  context "#async_as_codeowner?" do
    test "returns true if code owner reason is present" do
      @request.reasons.create!(
        reason_type: "codeowners",
        codeowners_tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740",
        codeowners_path: "CODEOWNERS",
        codeowners_line: 1,
        codeowners_pattern: /foobar/,
      )

      assert @request.async_as_codeowner?.sync, "not requested as code owner"
    end

    test "returns false it no reason is present" do
      refute @request.async_as_codeowner?.sync, "requested as code owner"
    end
  end

  context "#async_codeowner_reason" do
    test "returns code owner reason is present" do
      reason = @request.reasons.create!(
        reason_type: "codeowners",
        codeowners_tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740",
        codeowners_path: "CODEOWNERS",
        codeowners_line: 1,
        codeowners_pattern: /foobar/,
      )

      assert_equal reason, @request.async_codeowner_reason.sync
    end

    test "returns nothing if no reason is present" do
      assert_nil @request.async_codeowner_reason.sync
    end
  end

  context "notifications" do
    context "ignoring team notifications" do
      test "does not send notification for user review request if team member has ignored team notifications" do
        enable_feature_flag(:ignorable_team_notifications)
        opt_out_member = create(:user, login: "opt-out-member")
        notified_team = create(:team, organization: @org, privacy: :closed)
        @source.add_team notified_team, action: :write
        notified_team.add_member(opt_out_member)
        enable_notifications_for_user(opt_out_member)

        # Ignore team
        perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
          GitHub.newsies.ignore_list(opt_out_member, notified_team)
        end

        # Check the subscription
        assert_predicate notified_team.subscription_status(opt_out_member).value!, :ignored?

        # Create review request
        only = [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]
        perform_enqueued_jobs(only: only) do
          @pull.review_requests.create(reviewer: notified_team)
        end
        review_request_event = @pull.events.last.issue_event_notification

        assert @pull.direct_review_request_for(notified_team)
        # The opt_out_member should not receive the notification
        refute_delivered_email_notification(opt_out_member, review_request_event)

        comment = T.let(nil, T.untyped)
        # Perform action to cause fresh notifications to be generated for the team
        perform_enqueued_jobs(only: only) do
          comment = @pull.issue.comments.create!({ user: @forker, body: "hiya" })
        end

        # Notification deliveries should fail for opt_out_member
        refute_delivered_email_notification(opt_out_member, comment)
      end

      test "should still send notifications to team member that is not ignoring the team", skip_with_all_emus: true do
        enable_feature_flag(:ignorable_team_notifications)
        disable_feature_flag(:notifyd_pull_request_notify_email_and_web)
        opt_in_member = create(:user, :verified, login: "opt-in-member")
        notified_team = create(:team, organization: @org, privacy: :closed)
        @source.add_team notified_team, action: :write
        notified_team.add_member(opt_in_member)
        enable_notifications_for_user(opt_in_member)

        # Check the subscription
        assert_predicate notified_team.subscription_status(opt_in_member).value!, :subscribed?

        # Create review request
        only = [IssueCommentOrchestrationJob, SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]
        perform_enqueued_jobs(only: only) do
          @pull.review_requests.create(reviewer: notified_team)
        end
        review_request_event = @pull.events.last.issue_event_notification

        assert @pull.direct_review_request_for(notified_team)
        # The opt_in_member should receive the notification
        assert_delivered_web_notification(opt_in_member, review_request_event, "review_requested")
        assert_delivered_email_notification(opt_in_member, review_request_event, "review_requested")

        # Perform action to cause fresh notifications to be generated for the team
        comment = T.let(nil, T.untyped)
        perform_enqueued_jobs(only: only) do
          comment = @pull.issue.comments.create!({ user: @forker, body: "hiya" })
        end

        # Notification deliveries should sent for opt_in_member
        assert_delivered_web_notification(opt_in_member, comment, "review_requested")
        assert_delivered_email_notification(opt_in_member, review_request_event, "review_requested")
      end

      test "child team member ignoring child team should be notified if a parent is assigned as a reviewer", skip_with_all_emus: true do
        enable_feature_flag(:ignorable_team_notifications)
        disable_feature_flag(:notifyd_pull_request_notify_email_and_web)

        parent_team = create(:team, organization: @org, privacy: :closed)
        @source.add_team parent_team, action: :write

        child_team = create(:team, organization: @org, parent_team_id: parent_team.id, privacy: :closed)
        child_team_member = create(:user, :verified, login: "child-team-member")
        child_team.add_member(child_team_member)

        enable_notifications_for_user(child_team_member)

        # Check the subscription
        assert_predicate parent_team.subscription_status(child_team_member).value!, :subscribed?
        assert_predicate child_team.subscription_status(child_team_member).value!, :subscribed?

        # Child team member ignoring child team
        perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
          GitHub.newsies.ignore_list(child_team_member, child_team)
        end

        # Check the updated subscription
        assert_predicate child_team.subscription_status(child_team_member).value!, :ignored?
        assert_predicate parent_team.subscription_status(child_team_member).value!, :subscribed?

        # Create review request for parent team
        parent_review_request = T.let(nil, T.nilable(ReviewRequest))
        only = [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]
        perform_enqueued_jobs(only: only) do
          parent_review_request = @pull.review_requests.create(reviewer: parent_team)
        end
        assert @pull.direct_review_request_for(parent_team)

        parent_review_request_event = @pull.events.last.issue_event_notification
        # The child_team_member should receive the notification
        assert_delivered_email_notification(child_team_member, parent_review_request_event, "review_requested")

        # Clear last review requests
        parent_review_request&.destroy!
        @pull.reload

        # Clear last notifications
        ActionMailer::Base.deliveries.clear

        # Create review request for child team
        perform_enqueued_jobs(only: only) do
          @pull.review_requests.create(reviewer: child_team)
        end

        assert @pull.direct_review_request_for(child_team)

        child_review_request_event = @pull.events.last.issue_event_notification
        # The child_team_member should not receive the notification
        refute_delivered_email_notification(child_team_member, child_review_request_event)
      end

      test "child team member ignoring parent team should be notified if a child team is assigned as a reviewer", skip_with_all_emus: true do
        enable_feature_flag(:ignorable_team_notifications)
        disable_feature_flag(:notifyd_pull_request_notify_email_and_web)

        parent_team = create(:team, organization: @org, privacy: :closed)
        @source.add_team parent_team, action: :write

        child_team = create(:team, organization: @org, parent_team_id: parent_team.id, privacy: :closed)
        child_team_member = create(:user, :verified, login: "child-team-member")
        child_team.add_member(child_team_member)

        enable_notifications_for_user(child_team_member)

        # Check the subscription
        assert_predicate parent_team.subscription_status(child_team_member).value!, :subscribed?
        assert_predicate child_team.subscription_status(child_team_member).value!, :subscribed?

        # Child team member ignoring parent team
        perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
          GitHub.newsies.ignore_list(child_team_member, parent_team)
        end

        # Check the updated subscription
        assert_predicate parent_team.subscription_status(child_team_member).value!, :ignored?
        assert_predicate child_team.subscription_status(child_team_member).value!, :subscribed?

        # Create review request for parent team
        parent_review_request = T.let(nil, T.nilable(ReviewRequest))
        only = [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]
        perform_enqueued_jobs(only: only) do
          parent_review_request = @pull.review_requests.create(reviewer: parent_team)
        end
        assert @pull.direct_review_request_for(parent_team)

        parent_review_request_event = @pull.events.last.issue_event_notification
        # The child_team_member should not receive the notification from parent team
        refute_delivered_email_notification(child_team_member, parent_review_request_event)

        # Clear last review requests
        parent_review_request&.destroy!
        @pull.reload

        # Create review request for child team
        perform_enqueued_jobs(only: only) do
          @pull.review_requests.create(reviewer: child_team)
        end

        assert @pull.direct_review_request_for(child_team)

        child_review_request_event = @pull.events.last.issue_event_notification
        # The child_team_member should receive the notification from child team
        assert_delivered_email_notification(child_team_member, child_review_request_event, "review_requested")
      end

      test "team member ignoring a team is notified anyway if the organization has not enabled the feature", skip_with_all_emus: true do
        disable_feature_flag(:ignorable_team_notifications)
        disable_feature_flag(:notifyd_pull_request_notify_email_and_web)
        opt_out_member = create(:user, :verified, login: "opt-out-member")
        notified_team = create(:team, organization: @org, privacy: :closed)
        @source.add_team notified_team, action: :write
        notified_team.add_member(opt_out_member)
        enable_feature_flag(:ignorable_team_notifications, opt_out_member)
        enable_notifications_for_user(opt_out_member)

        assert GitHub.flipper[:ignorable_team_notifications].enabled?(opt_out_member)
        refute GitHub.flipper[:ignorable_team_notifications].enabled?(@org)

        # Ignore team
        perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
          GitHub.newsies.ignore_list(opt_out_member, notified_team)
        end

        # Check the subscription
        assert_predicate notified_team.subscription_status(opt_out_member).value!, :ignored?

        # Create review request
        only = [IssueCommentOrchestrationJob, SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]
        perform_enqueued_jobs(only: only) do
          @pull.review_requests.create(reviewer: notified_team)
        end
        review_request_event = @pull.events.last.issue_event_notification

        assert @pull.direct_review_request_for(notified_team)
        # The opt_out_member should not receive the notification
        assert_delivered_email_notification(opt_out_member, review_request_event, "review_requested")

        comment = T.let(nil, T.untyped)
        # Perform action to cause fresh notifications to be generated for the team
        perform_enqueued_jobs(only: only) do
          comment = @pull.issue.comments.create!({ user: @forker, body: "hiya" })
        end

        # Notification deliveries should fail for opt_out_member
        assert_delivered_email_notification(opt_out_member, comment, "review_requested")
      end
    end
  end
end

class DeferredReviewRequestTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @org = create(:organization, admin: @owner)
    @org.allow_private_repository_forking(actor: @owner)

    @team = create(:team, organization: @org, privacy: :closed)
    @forker = create(:user)
    @member = create(:user)
    @team.add_member(@member)

    @team.review_request_delegation_enabled = true
    @team.review_request_delegation_algorithm = :round_robin
    @team.save!

    @source = create(:private_repository, owner: @org, name: "source", from_example: :review_comment_fork)
    @source.add_team @team, action: :write
    @source.add_member @forker, action: :write

    @reviewer = create :user, login: "assignee-mcgee"
    create(:collaborator, collaborator: @reviewer, repository: @source)

    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)


    @issue = create(:issue, user: @forker, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @forker,
      )
    @issue.pull_request = @pull
  end

  test "a deferred review request remembers that it's deferred" do
    request = @pull.review_requests.create(reviewer: @reviewer, deferred: true)
    assert_predicate request, :deferred?

    request = ReviewRequest.find(request.id)
    assert_predicate request, :deferred?
  end

  test "creating a deferred review request does not notify state changes" do
    channel = GitHub::WebSocket::Channels.pull_request_review_state(@pull)
    GitHub::WebSocket.stubs(:notify_repository_channel).returns([])
    GitHub::WebSocket.expects(:notify_repository_channel)
      .with(@pull.repository, channel, has_key(:pull_request_id))
      .once

    review = @pull.review_requests.create(reviewer: @reviewer)
    review.destroy

    channel = GitHub::WebSocket::Channels.pull_request_review_state(@pull)
    GitHub::WebSocket.stubs(:notify_repository_channel).returns([])
    GitHub::WebSocket.expects(:notify_repository_channel)
      .with(@pull.repository, channel, has_key(:pull_request_id))
      .never

    @pull.review_requests.create(reviewer: @reviewer, deferred: true)
  end

  test "does not trigger a review_request event on the parent pull when created as deferred" do
    assert_no_difference("@issue.events.count") do
      @pull.review_requests.create!(reviewer: @reviewer, deferred: true)
    end
  end

  context "dismissal" do
    test "does not trigger a review_request_removed event on the parent pull when deferred" do
      @pull.convert_to_draft(user: @pull.user)
      review = @pull.review_requests.create!(reviewer: @reviewer, deferred: true)

      assert_no_difference("@issue.events.count") do
        review.update!(dismissed_at: Time.now)
      end
    end
  end

  context "importing" do
    test "skips specific callbacks during import" do
      GitHub.importing do
        request = @pull.review_requests.create!(reviewer: @reviewer, deferred: true)
        request.expects(:ensure_requested_team_is_in_valid_org).never
        request.expects(:ensure_requested_reviewer_is_a_collaborator).never
        request.expects(:trigger_review_requested_event).never
        request.expects(:trigger_review_request_removed_event).never

        request.save
      end
    end
  end

  context "#ready!" do
    test "triggers a review_request event on the parent pull" do
      request = @pull.review_requests.create!(reviewer: @reviewer, deferred: true)

      assert_difference("@issue.events.count", 1) do
        request.ready!(user: @forker)
      end

      review_request = @pull.review_requests.last
      request_event = @pull.events.last
      assert_equal "review_requested", request_event.event
      assert_equal @reviewer, request_event.subject
      assert_equal @forker, request_event.actor
      assert_equal review_request.id, request_event.review_request_id
    end

    test "delegates to team members" do
      request = @pull.review_requests.create!(reviewer: @team, deferred: true)

      request.ready!(user: @pull.user)

      assert_equal 1, @pull.review_requests.count, "Has one review request"
      assert_equal 1, @pull.review_requests.where(reviewer_type: "User", reviewer_id: @member.id).count, "Has one member review request"
    end

    test "does not trigger an event if the request is dismissed" do
      request = @pull.review_requests.create!(reviewer: @reviewer, deferred: true, dismissed_at: Time.now)

      assert_no_difference("@issue.events.count") do
        request.ready!(user: @forker)
      end

      refute_predicate ReviewRequest.find(request.id), :deferred?
    end

    test "does not delegate to team members when dismissed" do
      request = @pull.review_requests.create!(reviewer: @team, deferred: true, dismissed_at: Time.now)

      request.ready!(user: @pull.user)

      assert_equal 0, @pull.review_requests.count, "Has no review requests"
    end

    test "does not trigger an event if the request is fulfilled" do
      request = @pull.review_requests.create!(reviewer: @reviewer, deferred: true, dismissed_at: Time.now)

      review = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      review.approve!

      request.pull_request_reviews = [review]
      request.save

      assert_no_difference("@issue.events.count") do
        request.ready!(user: @forker)
      end

      refute_predicate ReviewRequest.find(request.id), :deferred?
    end

    test "does not delegate to team members when the request is fulfilled" do
      request = @pull.review_requests.create!(reviewer: @team, deferred: true)

      review = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      review.approve!

      request.pull_request_reviews = [review]
      request.save

      request.ready!(user: @pull.user)

      assert_equal 1, @pull.review_requests.count, "Has one review request"
      assert_equal 1, @pull.review_requests.where(reviewer_type: "Team", reviewer_id: @team.id).count, "Has one team review request"
    end

    test "triggers a review_request event if there is a pending review" do
      request = @pull.review_requests.create!(reviewer: @reviewer, deferred: true)

      review = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      assert_predicate review, :pending?

      assert_difference("@issue.events.count", 1) do
        request.ready!(user: @forker)
      end

      review_request = @pull.review_requests.last
      request_event = @pull.events.last
      assert_equal "review_requested", request_event.event
      assert_equal @reviewer, request_event.subject
      assert_equal @forker, request_event.actor
      assert_equal review_request.id, request_event.review_request_id
    end

    test "delegates to team members a review_request event if there is a pending review" do
      request = @pull.review_requests.create!(reviewer: @team, deferred: true)

      review = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      assert_predicate review, :pending?

      request.ready!(user: @pull.user)

      assert_equal 1, @pull.review_requests.count, "Has one review request"
      assert_equal 1, @pull.review_requests.where(reviewer_type: "User", reviewer_id: @member.id).count, "Has one member review request"
    end
  end

  test "sets `repository_id` from the pull" do
    review = create(:pull_request_review, pull_request: @pull)

    refute_nil review.repository_id
    assert_equal @pull.repository_id, review.repository_id
  end
end
