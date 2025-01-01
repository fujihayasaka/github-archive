# typed: true
# frozen_string_literal: true

require "test_helper"

class Api::App::ScheduledReminderHelpersTest < GitHub::TestCase
  include Api::App::ScheduledReminderHelpers
  attr_accessor :current_user, :current_integration, :current_org

  fixtures do
    @random_user = create :user, login: "random-user"
    @org = create :organization
    @another_org = create :organization
    @non_admin = create :user, login: "non-admin"
    @org.add_member(@non_admin)
    @current_user = @org.admin
    @another_org.add_member(@current_user)

    @slack_workspace = create(:reminder_slack_workspace, remindable: @org)
    @another_slack_workspace = create(:reminder_slack_workspace, remindable: @another_org)
    @teams_personal_workspace = create :reminder_teams_workspace, remindable: @org, teams_id: ReminderTeamsWorkspace::PERSONAL_REMINDER_TEAMS_ID, name: "Microsoft Teams"
    @personal_reminder = create :personal_reminder, user: @current_user, remindable: @org, slack_workspace: @slack_workspace
  end

  test "find_personal_reminder fetches personal reminder for an org and user", skip_enterprise: true do
    personal_reminder = find_personal_reminder(@org.id)
    assert_equal personal_reminder.id, @personal_reminder.id
    assert_equal personal_reminder.slack_workspace.id, @slack_workspace.id
  end

  test "get_personal_reminder_for_org fetches personal reminder and returns enhanced version", skip_enterprise: true do
    personal_reminder = get_personal_reminder_for_org(@org.id)
    reminder_event_subscriptions = @personal_reminder.event_subscriptions.map do |event_subscription|
      {
        event_type: event_subscription.event_type,
        options: event_subscription.options
      }
    end
    assert_equal personal_reminder[:id], @personal_reminder.id
    assert_equal personal_reminder[:workspace_id], @slack_workspace.slack_id
    assert_equal personal_reminder[:reminder_text], @personal_reminder.delivery_times_text
    assert_equal personal_reminder[:created_at], @personal_reminder.created_at
    assert_equal personal_reminder[:reminder_event_subscriptions], reminder_event_subscriptions
  end

  test "create_personal_reminder_for_org creates a new personal reminder", skip_enterprise: true do
    personal_reminder_params = {
      include_review_requests: true,
      include_team_review_requests: false,
      reminder_slack_workspace_id: @another_slack_workspace.id,
      time_zone_name: "Africa/Asmara",
      delivery_times: {
        days: %w[
          Monday
          Wednesday
          Friday
        ],
        times: [
          "6:00 AM",
          "7:30 AM",
          "9:00 AM",
        ],
      }.stringify_keys!,
      reminder_event_subscriptions: []
    }.stringify_keys!
    ReminderSlackWorkspaceMembership.create_or_update_membership(
      user_id: @current_user.id,
      reminder_slack_workspace_id: @another_slack_workspace.id,
    )
    personal_reminder = create_personal_reminder_for_org(@another_org.id, personal_reminder_params)
    refute_nil personal_reminder
    assert_equal personal_reminder.persisted?, true
    refute_nil personal_reminder.id
  end

  test "update_personal_reminder_for_org updates the same reminder", skip_enterprise: true do
    personal_reminder_params = {
      include_review_requests: true,
      include_team_review_requests: true,
      reminder_slack_workspace_id: @slack_workspace.id,
      time_zone_name: "Africa/Asmara",
      delivery_times: {
        days: %w[
          Monday
          Wednesday
          Friday
        ],
        times: [
          "6:00 AM",
          "7:30 AM",
          "9:00 AM",
        ],
      }.stringify_keys!,
      reminder_event_subscriptions: []
    }.stringify_keys!
    personal_reminder_id = @personal_reminder.id
    personal_reminder = update_personal_reminder_for_org(@personal_reminder, personal_reminder_params)
    refute_nil personal_reminder
    assert_equal personal_reminder.persisted?, true
    assert_equal personal_reminder.id, personal_reminder_id
  end

  test "create_reminder_params can set and remove teams", skip_enterprise: true do
    team = create :team, organization: @org, slug: "team"
    chatops_reminder = {
      teams: [team.slug],
    }.stringify_keys!

    reminder_params = create_reminder_params(@org, chatops_reminder)
    refute_nil reminder_params
    assert_equal [team.id], reminder_params["team_ids"]

    chatops_reminder = {
      teams: nil,
    }.stringify_keys!

    reminder_params = create_reminder_params(@org, chatops_reminder)
    refute_nil reminder_params
    assert_equal [], reminder_params["team_ids"]
  end

  test "create_update_personal_reminder_for_org creates or updates a personal reminder and returns the correct status", skip_enterprise: true do
    personal_reminder_params = {
      include_review_requests: true,
      include_team_review_requests: false,
      reminder_slack_workspace_id: @another_slack_workspace.id,
      time_zone_name: "Africa/Asmara",
      delivery_times: {
        days: %w[
          Monday
          Wednesday
          Friday
        ],
        times: [
          "6:00 AM",
          "7:30 AM",
          "9:00 AM",
        ],
      }.stringify_keys!,
      reminder_event_subscriptions: []
    }.stringify_keys!
    status = create_update_personal_reminder_for_org(@another_org.id, personal_reminder_params)
    assert_equal status, :created
    personal_reminder_params[:time_zone_name] = "Asia/Calcutta"
    status = create_update_personal_reminder_for_org(@another_org.id, personal_reminder_params)
    assert_equal status, :updated
  end

  test "delete_personal_reminder_for_org deletes the personal reminder for the given org", skip_enterprise: true do
    assert_equal delete_personal_reminder_for_org(@org.id), true
    assert_nil find_personal_reminder(@org.id)
  end

  test "get_personal_reminders_for_user fetches all personal reminders for users", skip_enterprise: true do
    @another_personal_reminder = create :personal_reminder, user: @current_user, remindable: @another_org, slack_workspace: @another_slack_workspace
    @personal_reminders = get_personal_reminders_for_user
    assert_equal @personal_reminders.count, 2
    refute_empty @personal_reminders.select { |personal_reminder| personal_reminder[:id] == @personal_reminder.id }
    refute_empty @personal_reminders.select { |personal_reminder| personal_reminder[:id] == @another_personal_reminder.id }
    refute_empty @personal_reminders.select { |personal_reminder| personal_reminder[:created_at] == @personal_reminder.created_at }
    refute_empty @personal_reminders.select { |personal_reminder| personal_reminder[:created_at] == @another_personal_reminder.created_at }
    refute_empty @personal_reminders.select { |personal_reminder| personal_reminder[:org_name] == @org.display_login }
    refute_empty @personal_reminders.select { |personal_reminder| personal_reminder[:org_name] == @another_org.display_login }
  end

  test "existing_workspace fetches existing workspace", skip_enterprise: true do
    @current_integration = create :slack_integration, owner: @org
    @current_org = @org
    refute_nil existing_workspace(@slack_workspace.slack_id)
  end

  test "existing_workspace creates workspace in case of Ms Teams personal scope", skip_enterprise: true do
    @current_integration = create :msteams_integration, owner: @org
    @current_org = @org
    @returned_workspace = existing_workspace(ReminderTeamsWorkspace::PERSONAL_REMINDER_TEAMS_ID)
    refute_nil @returned_workspace
    assert_equal @returned_workspace.teams_id, ReminderTeamsWorkspace::PERSONAL_REMINDER_TEAMS_ID
    assert_equal @returned_workspace.name, "Microsoft Teams"
  end
end
