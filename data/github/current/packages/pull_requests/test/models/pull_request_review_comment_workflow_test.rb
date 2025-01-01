# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewCommentWorkflowTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @reviewer = create(:user, login: "reviewer")
    @owner    = create(:user, login: "owner")
    @source = create(:repository, owner: @owner, name: "source", from_example: :review_comment_source)
    @forker = create(:user, :verified)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)
    @source.add_member @forker

    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, UpdateNotificationSummaryWithLocksJob, UpdateNotificationSummaryWithLocksJob]
    perform_enqueued_jobs(only: only) do
      @issue = create(:issue, user: @forker,
        repository: @source,
        title: "My great pull request"
      )
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

      @submitted_comment =
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: @reviewer, body: "hiya",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        ).submit!
    end
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  teardown { T.unsafe(GitHub).reset_stratocaster }

  test "can find all pending comments" do
    pending_comment =
      create(:pull_request_review_comment,
        pull_request: @pull,
        user: @reviewer, body: "hey this is a comment",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    assert_equal [pending_comment], PullRequestReviewComment.with_pending_state
    pending_comment.submit!
    assert_equal [], PullRequestReviewComment.with_pending_state
  end

  test "submitted is alias for is_submitted" do
    assert_predicate @submitted_comment, :submitted?
    assert_predicate @submitted_comment, :submitted?
  end

  test "tracks_references is false when pending" do
    comment = PullRequestReviewComment.new
    assert_predicate comment, :pending?
    refute_predicate comment, :track_references?
  end

  test "a legacy comment cannot be submitted again" do
    comment =
      create(:pull_request_review_comment,
        pull_request: @pull,
        user: @reviewer, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    comment.submit!
    assert_raises(RuntimeError, "Cannot submit a comment twice") do
      comment.submit!
    end
  end

  test "submitted comment is submitted" do
    assert_predicate @submitted_comment, :submitted?
  end

  test "submitted comment cannot be submitted again" do
    assert_raises(RuntimeError, "Cannot submit a comment twice") do
      @submitted_comment.submit!
    end
  end

  context "moving through the workflow" do
    test "adding a review does not raise MySQL query warnings" do
      assert_no_query_warnings do
        submitted_review = @pull.reviews.create!(
          user: @reviewer,
          head_sha: @pull.head_sha,
          body: "a submitted review",
        )
        submitted_review.approve!

        comment =
          create(:pull_request_review_comment,
            pull_request: @pull,
            user: @reviewer, body: "hey this is a comment",
            commit_id: @pull.head_sha,
            path: "aquaman.txt",
            original_position: 26
          )
        comment.add_review_for(user: @reviewer, pull_request: @pull, head_sha: @pull.head_sha)
        review = comment.pull_request_review
        assert_predicate review, :pending?
        assert_predicate comment, :pending?
      end
    end

    test "adds in a pending state" do
      comment =
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: @reviewer, body: "hey this is a comment",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        )

      comment.add_review_for(user: @reviewer, pull_request: @pull, head_sha: @pull.head_sha)

      assert_predicate comment, :pending?
      refute_predicate comment, :submitted?
    end

    test "moving to the submitted state" do
      comment =
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: @reviewer, body: "hey this is a comment",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        )

      comment.add_review_for(user: @reviewer, pull_request: @pull, head_sha: @pull.head_sha)

      assert_predicate comment, :pending?
      refute_predicate comment, :submitted?

      comment.submit!

      refute_predicate comment, :pending?
      assert_predicate comment, :submitted?
    end

    test "after_commit only fired once on create and approve" do
      watcher = create(:user)
      watcher.watch_repo @pull.repository

      PullRequestReview.any_instance.expects(:deliver_notifications).times(1).returns(true)

      comment = T.let(nil, T.nilable(PullRequestReviewComment))
      review = T.let(nil, T.nilable(PullRequestReview))
      perform_enqueued_jobs(only: [SubscribeAndNotifyJob]) do
        PullRequestReview.transaction do
          comment = build(:pull_request_review_comment,
            pull_request: @pull,
            user: @reviewer,
            body: "hiya",
            commit_id: @pull.head_sha,
            path: "aquaman.txt",
            original_position: 26,
          )
          # Jumping through hoops here to try to reproduce an issue with after_commits
          comment.add_review_for(user: @reviewer, pull_request: @pull, head_sha: @pull.head_sha)
          review = comment.pull_request_review
          comment.save!
          review.approve!
          review.save!
        end
      end
    end

    test "notifications only sent once for submit!" do
      disable_feature_flag(:notifyd_pull_request_notify_email_and_web)
      comment =
        build(:pull_request_review_comment,
          pull_request: @pull,
          user: @reviewer,
          body: "my PRRC comment",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
        )
      assert_difference("ActionMailer::Base.deliveries.size", 1) do
        assert_performed_with(job: SubscribeAndNotifyJob) do
          comment.submit!
        end
      end
      assert_match /my PRRC comment/, ActionMailer::Base.deliveries.last.to_s
    end

    test "rollup summaries are updated on submission of the review" do
      perform_enqueued_jobs(only: [SubscribeAndNotifyJob]) do
        comment = T.let(nil, T.nilable(PullRequestReviewComment))
        review = T.let(nil, T.nilable(PullRequestReview))

        assert_equal 1, @pull.review_comments.with_submitted_state.count

        # PullRequest plus one legacy submitted PRRC means we should have 2 "items" in the NotificationSummary
        summary = @pull.issue.get_notification_summary
        assert_equal 2, summary.items.size
        assert_equal @pull.number, summary.issue_number
        assert_equal "open", summary.issue_state
        assert_equal "My great pull request", summary.title

        perform_enqueued_jobs(only: [UpdateNotificationSummaryWithLocksJob, UpdateNotificationSummaryWithLocksJob]) do
          review = @pull.reviews.create!(user: @reviewer, head_sha: @pull.head_sha)

          5.times do |n|
            comment = build(:pull_request_review_comment,
              pull_request: @pull,
              user: @reviewer,
              body: "comment #{n}",
              commit_id: @pull.head_sha,
              path: "aquaman.txt",
              original_position: 26,
              pull_request_review_id: review,
            )
            review.review_comments << comment
            comment.save!
          end
        end
        assert_equal 5, review&.review_comments&.count
        assert_equal 1, @pull.review_comments.with_submitted_state.count

        # PullRequest plus one legacy submitted PRRC means we should have 2 "items" in the NotificationSummary
        summary = @pull.issue.get_notification_summary
        assert_equal 2, summary.items.size

        review = PullRequestReview.find(review&.id)
        perform_enqueued_jobs(only: [UpdateNotificationSummaryWithLocksJob, UpdateNotificationSummaryWithLocksJob]) do
          review.transaction do
            review.body = "ready!"
            review.save!
            assert review.reload.approve!
          end
        end

        assert_equal 6, @pull.review_comments.with_submitted_state.count

        summary = @pull.issue.get_notification_summary
        assert_equal 3, summary.items.size, "Expected 3 items to be summarized: Issue, legacy PullRequestReviewComment, and PullRequestReview"
        assert_equal summary.id, review.get_notification_summary.value&.id
      end
    end

    test ":created web hooks are queued once on submit!" do
      review = @pull.pending_review_for(
        user: @reviewer,
        head_sha: @pull.head_sha,
      )
      thread = review.build_thread
      comment = thread.build_first_comment(
        user: @reviewer,
        body: "my PRRC comment",
        diff: @pull.pull_comparison.diffs,
        path: "aquaman.txt",
        line: 26,
        side: :right,
      )

      review.save!

      refute_nil comment.pull_request_review

      Hook::Event::PullRequestReviewCommentEvent.expects(:queue).
        with(has_entry(action: :created)).
        once
      review.comment!
    end

    test "stratocaster notifications are triggered when the comment is submitted" do
      T.unsafe(GitHub).reset_stratocaster
      watcher = create(:user)
      watcher.watch_repo @pull.repository

      comment = nil
      comment = build(:pull_request_review_comment,
        pull_request: @pull,
        user: @reviewer,
        body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
      )
      comment.add_review_for(user: @reviewer, pull_request: @pull, head_sha: @pull.head_sha)
      comment.save!
      assert_predicate comment, :pending?
      refute_predicate comment, :submitted?

      event = GitHub.stratocaster_store.last
      assert_nil event

      review = comment.pull_request_review

      perform_enqueued_jobs(only: [ProcessEventJob]) do
        review.comment!
      end

      assert_equal 2, GitHub.stratocaster_store.all.size
      event = GitHub.stratocaster_store.last
      targets = Stratocaster.attributes_class_for(event.event_type).from_event(event).targets

      assert_equal "PullRequestReviewCommentEvent", event.event_type
      assert_equal 1, targets.size
    end
  end
end
