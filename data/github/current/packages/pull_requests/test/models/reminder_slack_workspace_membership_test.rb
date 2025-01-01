# typed: true
# frozen_string_literal: true
require "test_helper"

class ReminderSlackWorkspaceMembershipTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @slack_workspace = create(:reminder_slack_workspace)
  end

  context "create_or_update_membership" do
    test "creates new slack workspace membership" do
      assert_difference "ReminderSlackWorkspaceMembership.count" do
        membership = ReminderSlackWorkspaceMembership.create_or_update_membership(
          user_id: @user.id,
          reminder_slack_workspace_id: @slack_workspace.id,
        )
        assert_equal @user, membership.user
        assert_equal @slack_workspace, membership.slack_workspace
        refute_nil membership.created_at
        refute_nil membership.updated_at
      end
    end

    test "updates the timestamp of existing slack workspace memberships" do
      existing_membership = create(:reminder_slack_workspace_membership,
        user: @user,
        slack_workspace: @slack_workspace,
        created_at: 2.days.ago,
        updated_at: 2.days.ago,
      )

      assert_no_difference "ReminderSlackWorkspaceMembership.count" do
        membership = ReminderSlackWorkspaceMembership.create_or_update_membership(
          user_id: @user.id,
          reminder_slack_workspace_id: @slack_workspace.id,
        )
        assert_operator membership.updated_at, :>, existing_membership.updated_at
      end
    end
  end
end
