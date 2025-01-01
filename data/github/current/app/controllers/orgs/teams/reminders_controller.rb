# typed: true
# frozen_string_literal: true

class Orgs::Teams::RemindersController < Orgs::Controller
  include RemindersMethods
  include Orgs::TeamsHelper

  before_action :this_team_required
  before_action :feature_enabled?
  before_action :admin_on_team_required
  before_action :set_team_context_crumb, only: [:index]
  before_action :set_reminder!, only: [:show, :update, :destroy, :reminder_test]

  before_action { @selected_link = :reminders }

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:repository_suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :new], optional: true

  def index
    render(
      "orgs/teams/reminders/index",
      locals: {
        selected_nav_item: :settings,
        locked_to_team: this_team,
        slack_workspaces: slack_workspaces,
        organization: this_organization,
      },
      layout: "team")
  end

  # The rest of the controller methods are handled in `RemindersMethods`

  private

  def render_edit(reminder)
    render(
      "orgs/teams/reminders/edit",
      locals: {
        selected_nav_item: :settings,
        slack_workspaces: slack_workspaces,
        reminder: reminder,
        locked_to_team: this_team,
      },
      layout: "team")
  end

  def scope_reminders(reminder)
    case reminder
    when Hash, ActionController::Parameters
      reminder["team_ids"] = [this_team.id]
      reminder
    when ActiveRecord::Relation
      reminder_ids = ReminderTeamMembership.where(team: this_team).pluck(:reminder_id)
      reminder.where(id: reminder_ids)
    when Reminder
      if reminder.new_record?
        reminder.teams = [this_team]
        return reminder
      end
      return nil unless reminder.team_ids == [this_team.id]
      reminder
    end
  end

  def feature_enabled?
    render_404 unless RemindersMethods.reminders_enabled?(this_team)
  end
end
