# typed: true
# frozen_string_literal: true
require "test_helper"

class ReminderSlackWorkspaceTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
  end

  context "basics" do
    test "forces UTF-8 encoding" do
      slack_workspace = create(:reminder_slack_workspace, name: "Work 👨‍🚀")
      slack_workspace.reload # Reload from database to trigger encoding of column values

      assert_equal slack_workspace.name, "Work 👨‍🚀"
      assert_equal "UTF-8", slack_workspace.name.encoding.name
    end

    test "requires name" do
      slack_workspace = build(:reminder_slack_workspace, name: nil)
      slack_workspace.validate

      assert_equal slack_workspace.errors[:name], ["can't be blank"]
    end

    test "alt name is Slack" do
      slack_workspace = build(:reminder_slack_workspace, name: "TestWorkspace")

      assert_equal slack_workspace.class.alt_name, "Slack"
    end

    test "image path is correct" do
      slack_workspace = build(:reminder_slack_workspace, name: "TestWorkspace")

      assert_equal slack_workspace.class.image_url, "modules/site/integrators/slackhq.png"
    end
  end

  context "create_or_update_workspace" do
    test "creates new slack workspaces" do
      assert_difference "ReminderSlackWorkspace.count" do
        workspace = ReminderSlackWorkspace.create_or_update_workspace(
          name: "My super cool Slack team",
          remindable: @org,
          slack_id: "slack-id",
        )
        assert_equal "My super cool Slack team", workspace.name
        assert_equal @org, workspace.remindable
        assert_equal "slack-id", workspace.slack_id
        refute_nil workspace.created_at
        refute_nil workspace.updated_at
      end
    end

    test "rejects slack_id that is too long" do
      workspace = build(:reminder_slack_workspace,
        name: "Original name",
        slack_id: "a" * 49
      )
      refute_predicate workspace, :valid?
      assert_predicate workspace.errors[:slack_id], :any?
    end

    test "updates the name of existing slack workspaces" do
      existing_workspace = create(:reminder_slack_workspace,
        name: "Original name",
        remindable: @org,
        created_at: 2.days.ago,
        updated_at: 2.days.ago,
      )

      assert_no_difference "ReminderSlackWorkspace.count" do
        workspace = ReminderSlackWorkspace.create_or_update_workspace(
          name: "New name",
          remindable: existing_workspace.remindable,
          slack_id: existing_workspace.slack_id,
        )
        assert_equal "New name", workspace.name
        assert_operator workspace.updated_at, :>, existing_workspace.updated_at
      end
    end
  end
end
