# typed: true
# frozen_string_literal: true
require "test_helper"

class RemindersRealTimeEventTest < GitHub::TestCase
  EventSubjectMock = Struct.new(:to_global_id)
  fixtures do
    @user = create(:user)
    @org = create(:business_plus_organization, :with_slack)
    @other_org = create(:business_plus_organization)
    @org_repo = create(:repository, owner: @org)
    @other_org_repo = create(:repository, owner: @other_org)
    @personal_reminder = create(:personal_reminder, remindable: @org, user: @user)

    @example_args = {
      actor: :actor,
      context: :context,
      type: :comment,
      pull_request_ids: [1],
      reminder: :reminder,
      repository_id: 1,
      subject: :subject,
    }
  end

  test "attributes can be set on initialization" do
    real_time_event = Reminders::RealTimeEvent.new(**@example_args)

    assert_equal @example_args[:actor],            real_time_event.actor
    assert_equal @example_args[:context],          real_time_event.context
    assert_equal @example_args[:type],             real_time_event.type
    assert_equal @example_args[:pull_request_ids], real_time_event.pull_request_ids
    assert_equal @example_args[:reminder],         real_time_event.reminder
    assert_equal @example_args[:repository_id],    real_time_event.repository_id
    assert_equal @example_args[:subject],          real_time_event.subject
  end

  test "raises error when given invalid event type" do
    exception = assert_raises(ArgumentError) do
      Reminders::RealTimeEvent.new(**@example_args.merge(type: :florp))
    end

    assert_equal "Invalid event type: :florp", exception.message
  end

  context "#permitted?" do
    test "returns true when reminder user can access repository" do
      @org.add_admin(@user)

      real_time_event = Reminders::RealTimeEvent.new(
        **@example_args.merge(reminder: @personal_reminder, repository_id: @org_repo.id),
      )

      assert real_time_event.permitted?
    end

    test "returns false repository from another organization" do
      @org.add_admin(@user)
      @other_org.add_admin(@user)

      real_time_event = Reminders::RealTimeEvent.new(
        **@example_args.merge(reminder: @personal_reminder, repository_id: @other_org_repo.id),
      )

      refute real_time_event.permitted?
    end

    test "returns false when reminder user can't access repository" do
      real_time_event = Reminders::RealTimeEvent.new(
        **@example_args.merge(reminder: @personal_reminder, repository_id: @org_repo.id),
      )

      refute real_time_event.permitted?
    end
  end

  def build_event(overrides = {})
    Reminders::RealTimeEvent.new(**@example_args.merge(overrides))
  end

  context "#dedup_key" do
    test "creates key for user and subject for personal reminder" do
      subject = EventSubjectMock.new(to_global_id: "subject_global_id")
      real_time_event = build_event(reminder: @personal_reminder, subject: subject)

      assert_equal "#{@personal_reminder.user_id}-subject_global_id", real_time_event.dedup_key
    end

    test "creates key for Slack channel and subject for personal reminder" do
      subject = EventSubjectMock.new(to_global_id: "subject_global_id")
      reminder = create(:reminder, remindable: @org, slack_channel: "myslackchannel", user: @org.admin)
      real_time_event = build_event(reminder: reminder, subject: subject)

      assert_equal "myslackchannel-#{reminder.slack_workspace.slack_id}-subject_global_id", real_time_event.dedup_key
    end
  end
end
