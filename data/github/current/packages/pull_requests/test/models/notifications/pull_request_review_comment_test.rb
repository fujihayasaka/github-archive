# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationsPullRequestReviewCommentsTest < GitHub::TestCase
  include Notifications::TestHelper
  extend Notifications::TestHelper::ClassMethods

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
    options = options.reverse_merge(
      user: @author, path: "file10", original_position: 1)
    review = @pull.reviews.create! user: options[:user], head_sha: @pull.head_sha
    comment = create(:pull_request_review_comment, {
      pull_request: @pull,
      user: options[:user],
      body: (options[:body] || "sup"),
      commit_id: @pull.head_sha,
      pull_request_review_id: review.id,
    }.merge(options))

    assert review.comment!
    comment.reload
    assert_predicate comment, :submitted?
    refute_predicate comment, :legacy_comment?

    if comment.new_record?
      raise ActiveRecord::RecordInvalid.new(comment)
    end
    comment
  end

  test "creating a pending review comment doesn't subscribe mentions" do
    refute @thread.subscribed?(@owner)
    refute @thread.subscribed?(@reader)

    review = create(:pull_request_review, pull_request: @pull, user: @thread_author, body: "Hey @#{@owner}")
    comment = create(:pull_request_review_comment, pull_request: @pull, user: @thread_author, pull_request_review: review, body: "Hey @#{@reader}")

    refute_predicate comment, :submitted?
    refute @thread.subscribed?(@owner)
    refute @thread.subscribed?(@reader)

    # Submit review and make sure they're subscribed
    assert review.comment!
    assert @thread.subscribed?(@owner)
    assert @thread.subscribed?(@reader)
  end

  test "updating a pending review comment doesn't subscribe mentions" do
    refute @thread.subscribed?(@owner)
    refute @thread.subscribed?(@reader)

    review = create(:pull_request_review, pull_request: @pull, user: @thread_author, body: "Hey @#{@owner}")
    comment = create(:pull_request_review_comment, pull_request: @pull, user: @thread_author, pull_request_review: review, body: "Hey there")

    refute_predicate comment, :submitted?
    refute @thread.subscribed?(@owner)
    refute @thread.subscribed?(@reader)

    assert comment.update_body("Hey @#{@reader}", comment.user)
    refute @thread.subscribed?(@owner)
    refute @thread.subscribed?(@reader)

    # Submit review and make sure they're subscribed
    assert review.comment!
    assert @thread.subscribed?(@owner)
    assert @thread.subscribed?(@reader)
  end
end
