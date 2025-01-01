# typed: true
# frozen_string_literal: true
require "test_helper"

class RemindersReviewSubmissionFinderTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, :org_owned)
    @org = @repo.organization

    @amy = create(:user, login: "amy")
    @ben = create(:user, login: "ben")
    [@amy, @ben].each { |u| @org.add_member(u) }

    @amy_pull_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @amy, head_ref: "topic2")

    @amy_reminder = create(:personal_reminder, user: @amy, remindable: @org, event_types: [:review_submission])
    # Create to ensure unrelated reminders aren't notified
    create(:personal_reminder, user: @ben, remindable: @org, event_types: [:review_submission])

    @ben_review = @amy_pull_request.reviews.create!(user: @ben, head_sha: @amy_pull_request.head_sha, body: "the body")
  end

  test "Amy is notified when Ben approves her pull request" do
    @ben_review.approve!

    events = Reminders::ReviewSubmissionFinder.events(@ben_review)

    assert_equal 1, events.length

    event = events.first
    expected_context = { comment_body: @ben_review.body, review_state: :approved }

    assert_equal @ben,                   event.actor
    assert_equal expected_context,       event.context
    assert_equal :review_submission,     event.type
    assert_equal [@amy_pull_request.id], event.pull_request_ids
    assert_equal @amy_reminder,          event.reminder
    assert_equal @repo.id,               event.repository_id
    assert_equal @ben_review,            event.subject
  end

  test "Amy is notified when Ben requests changes on her pull request" do
    @ben_review.request_changes!

    events = Reminders::ReviewSubmissionFinder.events(@ben_review)

    assert_equal 1, events.length

    event = events.first
    expected_context = { comment_body: @ben_review.body, review_state: :changes_requested }

    assert_equal @ben,                   event.actor
    assert_equal expected_context,       event.context
    assert_equal :review_submission,     event.type
    assert_equal [@amy_pull_request.id], event.pull_request_ids
    assert_equal @amy_reminder,          event.reminder
    assert_equal @repo.id,               event.repository_id
    assert_equal @ben_review,            event.subject
  end

  test "Amy isn't notified when Ben comments on her pull request" do
    @ben_review.comment!

    events = Reminders::ReviewSubmissionFinder.events(@ben_review)

    assert_equal [], events
  end

  test "Amy isn't notified when she's not subscribed" do
    @amy_reminder.update!(event_types: [])
    @ben_review.approve!

    events = Reminders::ReviewSubmissionFinder.events(@ben_review)

    assert_equal [], events
  end
end
