# typed: true
# frozen_string_literal: true

require "test_helper"

class RemindersCommentFinderTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, :org_owned)
    @org = @repo.organization

    @amy = create(:user, login: "amy")
    @ben = create(:user, login: "ben")
    [@amy, @ben].each { |u| @org.add_member(u) }

    @amy_pull_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @amy, head_ref: "topic2")
    @amy_reminder = create(:personal_reminder, user: @amy, remindable: @org, event_types: [:comment])
    # Create to ensure unrelated reminders aren't notified
    create(:personal_reminder, user: @ben, remindable: @org, event_types: [:comment])
  end

  test "Amy is notified when Ben comments her pull request" do
    events = Reminders::CommentFinder.events(
      actor: @ben,
      body: "some comment",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: "some-url"
    )

    assert_equal 1, events.length

    event = events.first
    expected_context = { comment_body: "some comment", comment_html_url: "some-url" }

    assert_equal @ben,                   event.actor
    assert_equal expected_context,       event.context
    assert_equal :comment,               event.type
    assert_equal [@amy_pull_request.id], event.pull_request_ids
    assert_equal @amy_reminder,          event.reminder
    assert_equal @repo.id,               event.repository_id
    assert_equal :fake_subject,          event.subject
  end

  test "Amy isn't notified when she comments on her own pull request" do
    events = Reminders::CommentFinder.events(
      actor: @amy,
      body: "some comment",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: ""
    )

    assert_equal [], events
  end

  test "Amy isn't notified when the body is blank" do
    events = Reminders::CommentFinder.events(
      actor: @ben,
      body: "",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: ""
    )

    assert_equal [], events
  end

  test "Amy isn't notified when the body is nil" do
    events = Reminders::CommentFinder.events(
      actor: @ben,
      body: nil,
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: ""
    )

    assert_equal [], events
  end

  test "Amy isn't notified when she's not subscribed" do
    @amy_reminder.update!(event_types: [])

    events = Reminders::CommentFinder.events(
      actor: @ben,
      body: "some comment",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: ""
    )

    assert_equal [], events
  end
end
