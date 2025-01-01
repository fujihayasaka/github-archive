# typed: true
# frozen_string_literal: true
require "test_helper"

class ReminderSlackWorkspaceConnectorTest < GitHub::TestCase
  fixtures do
    @app    = create(:slack_integration)
    @org    = create(:business_plus_organization)
    @admin  = create(:user)
    @member = create(:user)

    @org.add_admin(@admin)
    @org.add_member(@member)
  end

  def build_payload(user: @admin, org: @org)
    {
      "workspace_name" => "Los Calientes",
      "workspace_id" => "T23456789",
      "enterprise_install" => false,
      "enterprise_name" => "",
      "state" => ReminderSlackWorkspaceConnector.encrypt(
        "user_id" => user.id,
        "organization_id" => org.id,
        "referring_path" => "/foo",
        "time" => Time.now.iso8601,
      ),
    }
  end

  def build_payload_for_enterprise_install(user: @admin, org: @org)
    {
      "enterprise_install" => true,
      "enterprise_name" => "Los Calientes enterprise",
      "workspace_id" => "",
      "workspace_name" => "",
      "state" => ReminderSlackWorkspaceConnector.encrypt(
        "user_id" => user.id,
        "organization_id" => org.id,
        "referring_path" => "/foo",
        "time" => Time.now.iso8601,
      ),
    }
  end

  def generate_jwt(payload, expires_in: nil, secret: GitHub.slack_integration_secret)
    payload["exp"] = expires_in.from_now.to_i if expires_in

    JWT.encode(payload, secret, "HS256")
  end

  context "#connect" do
    test "connects a Slack workspace to an organization" do
      connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
      jwt = generate_jwt(build_payload)

      connector.connect(jwt)

      slack_workspace = ReminderSlackWorkspace.last
      assert_equal "Los Calientes", T.must(slack_workspace).name
      assert_equal "T23456789", T.must(slack_workspace).slack_id
      assert_equal @org, T.must(slack_workspace).remindable
      assert T.must(slack_workspace).member?(@admin)
    end

    test "updates existing Slack workspace name" do
      payload = build_payload
      slack_workspace = create(:reminder_slack_workspace, remindable: @org, slack_id: payload["workspace_id"], name: "Old name")
      connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
      jwt = generate_jwt(payload)

      connector.connect(jwt)

      assert_equal "Los Calientes", slack_workspace.reload.name
    end

    test "adds org member to existing Slack workspace" do
      payload = build_payload(user: @member)
      slack_workspace = create(:reminder_slack_workspace, remindable: @org, slack_id: payload["workspace_id"])
      connector = ReminderSlackWorkspaceConnector.new(user: @member, organization: @org)
      jwt = generate_jwt(payload)

      connector.connect(jwt)

      assert slack_workspace.member?(@member)
    end

    test "sets referring_path" do
      connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
      jwt = generate_jwt(build_payload)

      connector.connect(jwt)

      assert_equal "/foo", connector.referring_path
    end

    test "sets workspace" do
      connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
      jwt = generate_jwt(build_payload)

      connector.connect(jwt)

      refute_nil connector.workspace
      assert_equal "T23456789", connector.workspace.slack_id
    end

    context "exceptional cases" do
      test "raises error when an enterprise is selected in reminder flow" do
        connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
        payload = build_payload_for_enterprise_install(user: @member)
        jwt = generate_jwt(payload)

        assert_raises ReminderSlackWorkspaceConnector::SelectedEnterpriseInRemindersError do
          connector.connect(jwt)
        end
      end

      test "raises error when bad JWT" do
        connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)

        assert_raises ReminderSlackWorkspaceConnector::JwtError do
          connector.connect("this ain't a jwt")
        end
      end

      test "raises error when expired JWT" do
        connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
        jwt = travel_to(10.minutes.ago) do
          generate_jwt(build_payload, expires_in: 1.minute)
        end

        assert_raises ReminderSlackWorkspaceConnector::JwtError do
          connector.connect(jwt)
        end
      end

      test "still works when JWT expired within leeway" do
        connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
        jwt = travel_to(10.minutes.ago) do
          generate_jwt(build_payload, expires_in: 8.minutes)
        end

        connector.connect(jwt)
      end

      test "raises error when state missing" do
        connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
        payload = build_payload
        payload.delete("state")
        jwt = generate_jwt(payload)

        assert_raises ReminderSlackWorkspaceConnector::StateMissingError do
          connector.connect(jwt)
        end
      end

      test "raises error when user_id in state doesn't match user" do
        connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
        payload = build_payload(user: @member)
        jwt = generate_jwt(payload)

        assert_raises ReminderSlackWorkspaceConnector::StateMismatchError do
          connector.connect(jwt)
        end
      end

      test "raises error when organization_id in state doesn't match org" do
        connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: create(:organization))
        jwt = generate_jwt(build_payload(user: @member))

        assert_raises ReminderSlackWorkspaceConnector::StateMismatchError do
          connector.connect(jwt)
        end
      end

      test "raises error when workspace_id missing" do
        connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
        payload = build_payload
        payload.delete("workspace_id")
        jwt = generate_jwt(payload)

        assert_raises ReminderSlackWorkspaceConnector::WorkspaceParamsMissingError do
          connector.connect(jwt)
        end
      end

      test "raises error when workspace_name missing" do
        connector = ReminderSlackWorkspaceConnector.new(user: @admin, organization: @org)
        payload = build_payload
        payload.delete("workspace_name")
        jwt = generate_jwt(payload)

        assert_raises ReminderSlackWorkspaceConnector::WorkspaceParamsMissingError do
          connector.connect(jwt)
        end
      end

      test "raises error when a non-admin org member attempts to connect new Slack workspace" do
        payload = build_payload(user: @member)
        connector = ReminderSlackWorkspaceConnector.new(user: @member, organization: @org)
        jwt = generate_jwt(payload)

        assert_raises ReminderSlackWorkspaceConnector::InsufficientPermissionsError do
          connector.connect(jwt)
        end
      end

      test "raises error when the slack integration reports an error" do
        payload = {
          "error" => "There was an error",
        }
        connector = ReminderSlackWorkspaceConnector.new(user: @member, organization: @org)
        jwt = generate_jwt(payload)

        slack_e = assert_raises ReminderSlackWorkspaceConnector::SlackIntegrationError do
          connector.connect(jwt)
        end

        assert_equal slack_e.message, payload["error"]
      end

      test "raises error when user who is not a member of the org attempts connect to an existing Slack workspace" do
        non_member = create(:user)
        payload = build_payload(user: non_member)
        slack_workspace = create(:reminder_slack_workspace, remindable: @org, slack_id: payload["workspace_id"])
        connector = ReminderSlackWorkspaceConnector.new(user: non_member, organization: @org)
        jwt = generate_jwt(payload)

        assert_raises ReminderSlackWorkspaceConnector::InsufficientPermissionsError do
          connector.connect(jwt)
        end
      end
    end
  end
end
