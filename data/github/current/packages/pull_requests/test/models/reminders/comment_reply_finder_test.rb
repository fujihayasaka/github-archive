# typed: true
# frozen_string_literal: true

require "test_helper"

class RemindersCommentReplyFinderTest < GitHub::TestCase
  fixtures do
    @amy = create(:user, login: "amy")
    @ben = create(:user, login: "ben")
    @max = create(:user, login: "max")

    @org = create(:organization)
    [@amy, @ben, @max].each { |u| @org.add_member(u) }

    # Amy forks the aquaman repository
    @source = create(:repository, owner: @org, name: "aquaman", from_example: :review_comment_source)
    @fork = create(:fork_repository, forker: @amy, fork_repo: @source, from_example: :review_comment_fork)

    # Amy opens a pull request
    @issue = create(:issue, user: @amy, repository: @source)
    @amy_pull_request = PullRequest.create_for(@source, base: "master", head: "#{@fork.user}:topic", user: @issue.user, issue: @issue)
    @issue.pull_request = @amy_pull_request

    @amy_reminder = create(:personal_reminder, user: @amy, remindable: @org, event_types: [:comment_reply])
    @ben_reminder = create(:personal_reminder, user: @ben, remindable: @org, event_types: [:comment_reply])
    @max_reminder = create(:personal_reminder, user: @max, remindable: @org, event_types: [:comment_reply])

    @ben_review = @amy_pull_request.reviews.create!(user: @ben, head_sha: @amy_pull_request.head_sha)
    @ben_comment = create(:pull_request_review_comment,
      pull_request: @amy_pull_request,
      pull_request_review: @ben_review,
      user: @ben,
      commit_id: @amy_pull_request.head_sha,
      path: "aquaman.txt",
      original_position: 21,
      body: "ship it",
    )

    @ben_review.comment!
  end

  def add_reply(body, user:, submit: true)
    review = @amy_pull_request.reviews.create!(user: user, head_sha: @amy_pull_request.head_sha)
    comment = @ben_comment.build_reply(review: review, body: body)
    comment.save!
    review.comment! if submit
    comment
  end

  test "Ben is notified when Amy replies to his comment" do
    comment = add_reply("hello", user: @amy)

    events = Reminders::CommentReplyFinder.events(comment)

    assert_equal 1, events.length

    event = events.first
    expected_context = { comment_body: comment.body, comment_html_url: comment.permalink }

    assert_equal @amy,                   event.actor
    assert_equal expected_context,       event.context
    assert_equal :comment_reply,         event.type
    assert_equal [@amy_pull_request.id], event.pull_request_ids
    assert_equal @ben_reminder,          event.reminder
    assert_equal @source.id,             event.repository_id
    assert_equal comment,                event.subject
  end

  test "anyone in thread is notified when comment is posted" do
    add_reply("hello", user: @amy)
    comment = add_reply("hello 2", user: @max)

    events = Reminders::CommentReplyFinder.events(comment)

    assert_equal 2, events.length
    assert_same_elements [@ben_reminder, @amy_reminder], events.map(&:reminder)
  end

  test "author isn't notified when they comment in a thread they're in" do
    comment = add_reply("hello", user: @ben)

    events = Reminders::CommentReplyFinder.events(comment)

    assert_equal [], events
  end

  test "only submitted comment author's are notified" do
    add_reply("hello", user: @amy, submit: false)
    comment = add_reply("hello", user: @max, submit: false)

    events = Reminders::CommentReplyFinder.events(comment)

    assert_equal 1, events.length
    assert_same_elements [@ben_reminder], events.map(&:reminder)
  end

  test "first comment in thread doesn't trigger notifications" do
    events = Reminders::CommentReplyFinder.events(@ben_comment)

    assert_equal [], events
  end

  test "Ben isn't notified when he's not subscribed" do
    @ben_reminder.update!(event_types: [])
    comment = add_reply("hello", user: @amy)

    events = Reminders::CommentReplyFinder.events(comment)

    assert_equal [], events
  end
end
