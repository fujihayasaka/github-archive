# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class ReminderSerializersTest < Api::SerializerTestCase
  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)

    make_trusted_oauth_apps_owner
    @slack_integration = create(:slack_integration)
    @slack_installation = make_integration_installation(
      integration: @slack_integration,
      target: @org,
    )

    @team = create(:team, organization: @org)
    @slack_workspace = create(:reminder_slack_workspace, remindable: @org, slack_id: 1200)
    @reminder = create(:reminder, slack_channel: "my-channel", remindable: @org, slack_workspace: @slack_workspace, created_at: 10.days.ago, user: @org.admin)
    @personal_reminder = create(:personal_reminder, remindable: @org, slack_workspace: @slack_workspace, created_at: 10.days.ago)

    @org_repo = create(:repository, owner: @org)
  end

  test "returns nil when given nil" do
    output = reminder(nil)
    assert_nil output
  end

  context "reminder" do
    test "serializes a reminder" do
      output = reminder(@reminder)
      assert_equal @reminder.id, output["id"]
      assert_equal "1200", output["workspace_id"]
      assert_equal "https://github.com/organizations/#{@org.to_param}/settings/reminders/#{@reminder.to_param}", output["html_url"]
      assert_equal "my-channel", output["channel_id"]
      assert_equal @reminder.global_relay_id, output["node_id"]
      assert_equal @reminder.created_at.getutc.iso8601, output["created_at"]
      assert_equal @reminder.updated_at.getutc.iso8601, output["updated_at"]
      assert_equal [{ "day" => "Monday", "time" => "9:00 AM" }], output["delivery_times"]
      assert_equal "Pacific Time (US & Canada)", output["time_zone_name"]
    end

    test "uses team url for team reminders" do
      @reminder.teams = [@team]
      output = reminder(@reminder)
      assert_equal @reminder.id, output["id"]
      assert_equal "https://github.com/orgs/#{@org.to_param}/teams/#{@team.to_param}/settings/reminders/#{@reminder.to_param}", output["html_url"]
    end

    test "includes delivery times" do
      create(:reminder_delivery_time, schedulable: @reminder, day: "Tuesday", time: "11:00 AM")
      output = reminder(@reminder)
      assert_equal [{
        "day" => "Monday",
        "time" => "9:00 AM",
      }, {
        "day" => "Tuesday",
        "time" => "11:00 AM",
      }], output["delivery_times"]
    end

    test "includes realtime events" do
      output = reminder(@reminder)
      assert_equal [], output["realtime_events"]
    end

    test "doesn't include recipient" do
      output = reminder(@reminder)
      refute_includes output.keys, "recipient"
    end
  end

  context "personal reminder" do
    test "serializes a personal reminder" do
      output = reminder(@personal_reminder)
      assert_equal @personal_reminder.id, output["id"]
      assert_equal "1200", output["workspace_id"]
      assert_equal "https://github.com/settings/reminders/#{@org.to_param}", output["html_url"]
      assert_equal @personal_reminder.global_relay_id, output["node_id"]
      assert_equal @personal_reminder.created_at.getutc.iso8601, output["created_at"]
      assert_equal @personal_reminder.updated_at.getutc.iso8601, output["updated_at"]
      assert_equal [{ "day" => "Monday", "time" => "9:00 AM" }], output["delivery_times"]
      assert_equal "Pacific Time (US & Canada)", output["time_zone_name"]
    end

    test "doesn't include channel" do
      output = reminder(@personal_reminder)
      refute_includes output.keys, "channel_id"
    end

    test "includes delivery times" do
      create(:reminder_delivery_time, schedulable: @personal_reminder, day: "Tuesday", time: "11:00 AM")
      output = reminder(@personal_reminder)
      assert_equal [{
        "day" => "Monday",
        "time" => "9:00 AM",
      }, {
        "day" => "Tuesday",
        "time" => "11:00 AM",
      }], output["delivery_times"]
    end

    test "includes realtime events" do
      @personal_reminder.update!(event_types: %w[comment review_request])
      output = reminder(@personal_reminder)
      assert_same_elements %w[comment review_request], output["realtime_events"]
    end

    test "includes recipient" do
      output = reminder(@personal_reminder)
      assert_equal @personal_reminder.user.login, output["recipient"]["login"]
    end
  end

  context "context" do
    test "returns context with event_type embedded" do
      output = reminder_context({ foo: 1 }, event_type: "pull_request_opened")
      assert_equal({ "event" => "pull_request_opened", "foo" => 1 }, output)
    end

    test "returns empty array if no event_type is sent" do
      output = reminder_context({ foo: 1 })
      assert_equal({}, output)
    end

    test "includes label when pull_request_labeled" do
      label = create(:label, repository: @org_repo)
      output = reminder_context({ label_id: label.id }, { event_type: "pull_request_labeled", repository: @org_repo })
      assert_equal label.name, output["label"]["name"]
      refute_includes output.keys, "label_id"
    end

    test "retains label_id if the label can't be found" do
      output = reminder_context({ label_id: -1 }, { event_type: "pull_request_labeled", repository: @org_repo })
      assert_equal({ "event" => "pull_request_labeled", "label_id" => -1 }, output)
    end
  end
end
