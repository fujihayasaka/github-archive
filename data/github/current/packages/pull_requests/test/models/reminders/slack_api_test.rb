# typed: false
# frozen_string_literal: true
require "test_helper"

class RemindersSlackApiTest < GitHub::TestCase
  include SlackApiTestHelper

  fixtures do
    @org = create(:organization, :with_slack)
    @repo = create(:repository, owner: @org)
    @reminder = create(:reminder, remindable: @org, user: @org.admin)
  end

  def stub_channel_status(response_data, status: 200)
    service_base = "_slack" if GitHub.enterprise?
    url = URI.join(GitHub.slack_integration_api_url, "#{service_base}/slack/v2/validate_channel").to_s
    request = stub_request(:post, url)

    request.to_return({
      status: status,
      body: response_data.to_json,
    })
  end

  def extract_payload_from(request)
    data = JSON.parse(request.body)
    secret = GitHub.slack_integration_secret

    JWT.decode(data.fetch("state"), secret, true, algorithm: "HS256").first
  end

  test "returns error when response 400s" do
    @reminder.slack_workspace.update(slack_id: "T74MJ8DTK") # Github Slack Dev
    @reminder.update(slack_channel: "julian-testing")

    stub_request_to_slack_int_api(status: 400, response: "Error: uuid is missing", headers: {})

    success, response = Reminders::SlackApi.post_reminder_change_to_channel(
      reminder_url: "https://example.com",
      reminder: @reminder,
      user: @org.admin,
      action: "created",
    )
    refute success, "should not have been successful"
    assert_equal "Error: uuid is missing", response
  end

  test "successful request" do
    @reminder.slack_workspace.update(slack_id: "T74MJ8DTK") # Github Slack Dev
    @reminder.update(slack_channel: "julian-testing")

    stub_request_to_slack_int_api(status: 200, response: {
      ok: true,
      channel: "CN8V5U4LD",
      ts: "1581550585.000600",
      message: {
        bot_id: "B8GU1PW8H",
        type: "message",
        text: "<https://github.com/user-3cbc1557bebddc131c4b0bf1|user-3cbc1557bebddc131c4b0bf1> has created a reminder on this channel. <https://github.com/organizations/testorg-31dc35d7f7efb1a1/settings/reminders/752|Manage reminder>",
        user: "U8HDX7G58",
        ts: "1581550585.000600",
        team: "T74MJ8DTK",
        bot_profile: {},
        response_metadata: {},
      },
    }, headers: {})

    success, response = Reminders::SlackApi.post_reminder_change_to_channel(
      reminder_url: "https://example.com",
      reminder: @reminder,
      user: @org.admin,
      action: "created",
    )
    assert success, "should have been successful"
    assert_kind_of Hash, response
    assert response["ok"], "should have been ok"
    assert_equal "CN8V5U4LD", response["channel"]
  end

  test "unsuccessful request" do
    @reminder.slack_workspace.update(slack_id: "T74MJ8DTK") # Github Slack Dev
    @reminder.update(slack_channel: "not-exist")

    stub_request_to_slack_int_api(status: 422, response: { error: "channel_not_found" }, headers: {})

    success, response = Reminders::SlackApi.post_reminder_change_to_channel(
      reminder_url: "https://example.com",
      reminder: @reminder,
      user: @org.admin,
      action: "created",
    )
    refute success, "should not have been successful"
    assert_equal({ "error" => "channel_not_found" }, response)
  end

  test "request times out" do
    stub_request_to_slack_int_api(timeout: true)
    success, response = Reminders::SlackApi.post_reminder_change_to_channel(
      reminder_url: "https://example.com",
      reminder: @reminder,
      user: @org.admin,
      action: "created",
    )
    refute success, "should be false when timing out"
    assert_equal "execution expired", response
  end

  test "maps to false when connection read timeout is throw" do
    stub_request_to_slack_int_api(exceptions: Net::ReadTimeout)
    success, response = Reminders::SlackApi.post_reminder_change_to_channel(
      reminder_url: "https://example.com",
      reminder: @reminder,
      user: @org.admin,
      action: "created",
    )
    refute success, "should be false when timing out"
  end

  test "maps to false when connection open timeout is throw" do
    stub_request_to_slack_int_api(exceptions: Net::OpenTimeout)
    success, response = Reminders::SlackApi.post_reminder_change_to_channel(
      reminder_url: "https://example.com",
      reminder: @reminder,
      user: @org.admin,
      action: "created",
    )
    refute success, "should be false when timing out"
  end

  context "with scheduled_reminders_add_by_channel_id_or_name enabled" do
    test "non-existent user uses ghost" do
      Reminders::SlackApi.expects(:send_request)
      GitHub.flipper[:scheduled_reminders_add_by_channel_id_or_name].enable

      Reminders::SlackApi.expects(:sign_payload).with(equals(
        github_user_login: User.ghost.display_login,
        action: "created",
        reminder_link: "https://example.com",
        workspace_id: @reminder.slack_workspace.slack_id,
        channel_id_or_name: @reminder.slack_channel,
      ))

      Reminders::SlackApi.post_reminder_change_to_channel(
        reminder_url: "https://example.com",
        reminder: @reminder,
        user: nil,
        action: "created",
      )
    end

    test "non-existent uses channel name" do
      Reminders::SlackApi.expects(:send_request)
      @reminder.slack_channel_id = nil
      @reminder.save(validate: false)
      GitHub.flipper[:scheduled_reminders_add_by_channel_id_or_name].enable

      Reminders::SlackApi.expects(:sign_payload).with(equals(
        github_user_login: User.ghost.display_login,
        action: "created",
        reminder_link: "https://example.com",
        workspace_id: @reminder.slack_workspace.slack_id,
        channel_id_or_name: @reminder.slack_channel, # Channel name used here
      ))

      Reminders::SlackApi.post_reminder_change_to_channel(
        reminder_url: "https://example.com",
        reminder: @reminder,
        user: nil,
        action: "created",
      )
    end
  end

  context "with scheduled_reminders_add_by_channel_id_or_name disabled" do
    test "non-existent user uses ghost" do
      Reminders::SlackApi.expects(:send_request)
      GitHub.flipper[:scheduled_reminders_add_by_channel_id_or_name].disable


      Reminders::SlackApi.expects(:sign_payload).with(equals(
        github_user_login: User.ghost.display_login,
        action: "created",
        reminder_link: "https://example.com",
        workspace_id: @reminder.slack_workspace.slack_id,
        channel_name: @reminder.slack_channel,
      ))

      Reminders::SlackApi.post_reminder_change_to_channel(
        reminder_url: "https://example.com",
        reminder: @reminder,
        user: nil,
        action: "created",
      )
    end

    test "non-existent uses channel name" do
      Reminders::SlackApi.expects(:send_request)
      @reminder.slack_channel_id = nil
      @reminder.save(validate: false)
      GitHub.flipper[:scheduled_reminders_add_by_channel_id_or_name].disable

      Reminders::SlackApi.expects(:sign_payload).with(equals(
        github_user_login: User.ghost.display_login,
        action: "created",
        reminder_link: "https://example.com",
        workspace_id: @reminder.slack_workspace.slack_id,
        channel_name: @reminder.slack_channel, # Channel name used here
      ))

      Reminders::SlackApi.post_reminder_change_to_channel(
        reminder_url: "https://example.com",
        reminder: @reminder,
        user: nil,
        action: "created",
      )
    end
  end

  test "non-json response" do
    stub_request_to_slack_int_api(status: 500, response: "Server Error", headers: {})

    success, response = Reminders::SlackApi.post_reminder_change_to_channel(
      reminder_url: "https://example.com",
      reminder: @reminder,
      user: @org.admin,
      action: "created",
    )
    refute success, "should not have been successful"
    assert_equal "Server Error", response
  end

  test "raises if reminder is not valid" do
    reminder = build(:reminder, remindable: @org, user: @org.admin)
    reminder.slack_workspace = nil
    refute_predicate reminder, :valid?

    err = assert_raises(ArgumentError) do
      Reminders::SlackApi.post_reminder_change_to_channel(
        reminder_url: "https://example.com",
        reminder: reminder,
        user: @org.admin,
        action: "created",
      )
    end

    assert_equal "Can't send message to Slack, reminder is not valid", err.message
  end

  test "payload contains UUID" do
    payload = nil
    service_base = "/_slack" if GitHub.enterprise?
    stub_request(:post, URI.join(GitHub.slack_integration_api_url, "#{service_base}/slack/v2/post_reminder_change").to_s)
      .to_return(body: -> (request) {
        payload = extract_payload_from(request)
        ""
      })

    success, response = Reminders::SlackApi.post_reminder_change_to_channel(
      reminder_url: "https://example.com",
      reminder: @reminder,
      user: @org.admin,
      action: "created",
    )

    assert payload["uuid"]
  end

  context "#channel_status" do
    test "channel is found" do
      stub_channel_status({ workspace_id: "T0001", channel_id: "C0001", status: "found" })

      status = Reminders::SlackApi.channel_status("C0001", workspace_id: "T0001")
      assert_equal "found", status
    end

    test "channel isn't found" do
      stub_channel_status({ workspace_id: "T0001", channel_id: "C0001", status: "not_found" })

      status = Reminders::SlackApi.channel_status("C0001", workspace_id: "T0001")
      assert_equal "not_found", status
    end

    test "request fails" do
      stub_channel_status({}, status: 404)

      status = Reminders::SlackApi.channel_status("C0001", workspace_id: "T0001")
      assert_equal "unknown", status
    end
  end

  # https://github.com/github/slack/issues/5666
  test "uses display_login for github_user_login" do
    enterprise_org = create(:organization, :with_slack, :enterprise_managed_organization)
    enterprise_repo = create(:repository, owner: enterprise_org, from_example: :repository_test_simple)
    enterprise_user = enterprise_org.admin
    reminder = create(:reminder, remindable: enterprise_org, user: enterprise_user)

    Reminders::SlackApi.expects(:send_request)

    Reminders::SlackApi.expects(:sign_payload).with(equals(
      github_user_login: enterprise_user.display_login,
      action: "updated",
      reminder_link: "https://example.com",
      workspace_id: reminder.slack_workspace.slack_id,
      channel_name: reminder.slack_channel,
    ))

    Reminders::SlackApi.post_reminder_change_to_channel(
      reminder_url: "https://example.com",
      reminder: reminder,
      user: enterprise_user,
      action: "updated",
    )
  end if GitHub.multi_tenant_enterprise?
end
