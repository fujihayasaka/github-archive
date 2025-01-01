# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationsPullRequestReviewTest < GitHub::TestCase
  include Notifications::TestHelper
  extend ClassMethods

  shared_notification_tests!
  shared_mention_tests!

  fixtures do
    @owner, @author, @thread_author, @reader = create_users :owner, :author, :threadauthor, :reader
    @org, @team = create_org @owner
    @org.allow_private_repository_forking(actor: @owner)
    @list = create :private_repository, owner: @org, name: "repo", from_example: :pull_request_source
    @team.add_repository(@list, :push)
    @fork = create(:fork_repository, forker: @thread_author, fork_repo: @list, from_example: :pull_request_fork)

    @thread = create :issue, :subscribed_author, user: @thread_author, repository: @list
    @pull = create :pull_request, issue: @thread,
      base_repository: @list,
      base_user: @org,
      base_ref: "master",
      head_repository: @fork,
      head_user: @thread_author,
      head_ref: "topic"

    Organization.update_all plan: "free" # lets us mark author as spammy
    @visitor = create_users :visitor
  end

  def trigger_notifications(options = {})
    options = options.reverse_merge(user: @author, body: "Looks good!")

    review = @pull.reviews.create!(head_sha: @pull.head_sha,
      user: options[:user],
      body: options[:body])

    review = review.reload

    assert_equal @author, review.user
    assert_equal @thread_author, review.notifications_thread.user

    assert_predicate review, :pending?

    assert review.approve!

    review
  end

  test "enqueues 1 SubscribeAndNotifyJob job on submission" do
    review = create(:pull_request_review, pull_request: @pull, user: @author)
    assert_predicate review, :pending?

    assert_performed_jobs 1, only: SubscribeAndNotifyJob do
      review.body = "Hey @#{@reader}"
      assert review.comment!
    end
  end

  test "enqueues 1 SubscribeAndNotifyJob when submitted review body is updated" do
    review = create(:pull_request_review, pull_request: @pull, user: @author, body: "LGTM")
    assert_predicate review, :pending?

    assert_performed_jobs 1, only: SubscribeAndNotifyJob do
      assert review.comment!
    end

    assert_performed_jobs 1, only: UpdateSubscriptionsAndNotifyJob do
      review.update_body("Hey @#{@reader}", review.user)
    end
  end

  test "enqueues 0 SubscribeAndNotifyJob jobs when pending review body is updated" do
    review = create(:pull_request_review, pull_request: @pull, user: @author, body: "LGTM")
    assert_predicate review, :pending?

    assert_performed_jobs 0, only: SubscribeAndNotifyJob do
      review.update_body("Hey @#{@reader}", review.user)
    end
  end
end
