# typed: true
# frozen_string_literal: true

require "test_helper"

class ReminderTeamsWorkspaceTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
  end

  context "basics" do
    test "forces UTF-8 encoding" do
      teams_workspace = create(:reminder_teams_workspace, name: "Work 👨‍🚀")
      teams_workspace.reload # Reload from database to trigger encoding of column values

      assert_equal teams_workspace.name, "Work 👨‍🚀"
      assert_equal "UTF-8", teams_workspace.name.encoding.name
    end

    test "requires name" do
      teams_workspace = build(:reminder_teams_workspace, name: nil)
      teams_workspace.validate

      assert_equal teams_workspace.errors[:name], ["can't be blank"]
    end

    test "alt name is Teams" do
      teams_workspace = build(:reminder_teams_workspace, name: "TeamsTestWorkspace")

      assert_equal teams_workspace.class.alt_name, "Microsoft Teams"
    end

    test "image path is correct" do
      teams_workspace = build(:reminder_teams_workspace, name: "TeamsTestWorkspace")

      assert_equal teams_workspace.class.image_url, "modules/site/integrators/microsoftteams.png"
    end
  end

  context "create_or_update_workspace" do
    test "creates new teams workspaces" do
      assert_difference "ReminderTeamsWorkspace.count" do
        workspace = ReminderTeamsWorkspace.create_or_update_workspace(
          name: "My super cool MS Teams team",
          remindable: @org,
          teams_id: "teams-id",
        )
        assert_equal "My super cool MS Teams team", workspace.name
        assert_equal @org, workspace.remindable
        assert_equal "teams-id", workspace.teams_id
        refute_nil workspace.created_at
        refute_nil workspace.updated_at
      end
    end

    test "updates the name of existing teams workspaces" do
      existing_workspace = create(:reminder_teams_workspace,
        name: "Original name",
        remindable: @org,
        created_at: 2.days.ago,
        updated_at: 2.days.ago,
      )

      assert_no_difference "ReminderTeamsWorkspace.count" do
        workspace = ReminderTeamsWorkspace.create_or_update_workspace(
          name: "New name",
          remindable: existing_workspace.remindable,
          teams_id: existing_workspace.teams_id,
        )
        assert_equal "New name", workspace.name
        assert_operator workspace.updated_at, :>, existing_workspace.updated_at
      end
    end
  end
end
