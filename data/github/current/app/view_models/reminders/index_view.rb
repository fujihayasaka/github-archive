# typed: true
# frozen_string_literal: true

class Reminders::IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include UrlHelpers

  attr_reader :slack_workspaces, :organization, :locked_to_team, :slack_installation

  def can_add_slack_workspace?
    organization.present? && organization.adminable_by?(current_user)
  end

  def grouped_reminders
    return @grouped_reminders if defined?(@grouped_reminders)

    reminder_ids = ReminderTeamMembership.where(team: locked_to_team).pluck(:reminder_id) if locked_to_team

    @grouped_reminders = slack_workspaces.each_with_object({}) do |workspace, acc|
      base_query = workspace.reminders.preload(:delivery_times, :repository_links, :team_memberships)

      acc[workspace] = if locked_to_team
        base_query.tied_to_single_team.where(reminders: {  id: reminder_ids })
      else
        base_query
      end
    end
  end

  def reminders_present?
    grouped_reminders.any? { |_slack_workspace, reminders| reminders.present? }
  end

  def can_edit_reminder?(reminder)
    return true if locked_to_team.nil?
    # Can only edit a reminder if it is the current team only
    # Multi-team reminders must be managed at the org level
    reminder.team_ids == [locked_to_team.id]
  end

  def slack_installation_outdated?
    Orgs::RemindersHelper.client_installation_outdated?(slack_installation)
  end
end
