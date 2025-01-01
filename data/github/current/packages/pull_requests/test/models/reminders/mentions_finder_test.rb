# typed: true
# frozen_string_literal: true

require "test_helper"

class RemindersMentionFinderTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, :org_owned)
    @org = @repo.organization

    @amy = create(:user, login: "amy")
    @ben = create(:user, login: "ben")
    @max = create(:user, login: "max")
    [@amy, @ben].each { |u| @org.add_member(u) }

    @amy_pull_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @amy, head_ref: "topic2")

    @amy_reminder = create(:personal_reminder, user: @amy, remindable: @org, event_types: [:mention])
    @ben_reminder = create(:personal_reminder, user: @ben, remindable: @org, event_types: [:mention])
    @max_reminder = create(:personal_reminder, user: @max, remindable: @org, event_types: [:mention])
  end

  test "Amy is notified when Ben mentions her on her pull request" do
    events = Reminders::MentionFinder.events(
      actor: @ben,
      body: "hi @amy",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: "foo-url",
    )

    assert_equal 1, events.length

    event = events.first
    expected_context = { comment_body: "hi @amy", comment_html_url: "foo-url" }

    assert_equal @ben,                   event.actor
    assert_equal expected_context,       event.context
    assert_equal :mention,               event.type
    assert_equal [@amy_pull_request.id], event.pull_request_ids
    assert_equal @amy_reminder,          event.reminder
    assert_equal @repo.id,               event.repository_id
    assert_equal :fake_subject,          event.subject
  end

  test "Max is notified when Ben mentions her on someone else's pull request" do
    events = Reminders::MentionFinder.events(
      actor: @ben,
      body: "hi @max",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: "foo-url",
    )

    assert_equal 1, events.length

    event = events.first
    expected_context = { comment_body: "hi @max", comment_html_url: "foo-url" }

    assert_equal @ben,                   event.actor
    assert_equal expected_context,       event.context
    assert_equal :mention,               event.type
    assert_equal [@amy_pull_request.id], event.pull_request_ids
    assert_equal @max_reminder,          event.reminder
    assert_equal @repo.id,               event.repository_id
    assert_equal :fake_subject,          event.subject
  end

  test "multiple people are notified when mentioned" do
    events = Reminders::MentionFinder.events(
      actor: @ben,
      body: "hi @amy @max",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: "foo-bar",
    )

    assert_equal 2, events.length
    assert_same_elements [@amy_reminder, @max_reminder], events.map(&:reminder)
  end

  test "mentioning someone twice only notifies them once" do
    events = Reminders::MentionFinder.events(
      actor: @ben,
      body: "hi @amy @amy",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: "foo-bar",
    )

    assert_equal 1, events.length
    assert_same_elements [@amy_reminder], events.map(&:reminder)
  end

  test "Ben isn't notified when he mentions himself" do
    events = Reminders::MentionFinder.events(
      actor: @ben,
      body: "hi @ben",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: "foo-bar",
    )

    assert_equal [], events
  end

  test "no one is notified when a non-existent username is mentioned" do
    events = Reminders::MentionFinder.events(
      actor: @ben,
      body: "hi @asdf",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: "foo-bar",
    )

    assert_equal [], events
  end

  test "no one is notified when body is nil" do
    events = Reminders::MentionFinder.events(
      actor: @ben,
      body: nil,
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: "foo-bar",
    )

    assert_equal [], events
  end

  test "Amy isn't notified when she's not subscribed" do
    @amy_reminder.update!(event_types: [])

    events = Reminders::MentionFinder.events(
      actor: @ben,
      body: "hi @amy",
      pull_request: @amy_pull_request,
      subject: :fake_subject,
      url: "foo-bar",
    )

    assert_equal [], events
  end

  test "Amy isn't notified when she's subscribed to another org" do
    other_repo = create(:repository, :org_owned)
    amy_other_pull_request = create(:pull_request, :disable_disk_access, repository: other_repo, user: @amy, head_ref: "topic2")

    events = Reminders::MentionFinder.events(
      actor: @ben,
      body: "hi @amy",
      pull_request: amy_other_pull_request,
      subject: :fake_subject,
      url: "foo-bar",
    )

    assert_equal [], events
  end
end
