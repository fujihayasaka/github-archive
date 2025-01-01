# typed: false
# frozen_string_literal: true

module Orgs::RemindersHelper
  def self.client_to_workspace_mapping(client_app)
    case client_app
    when :msteams
      ReminderTeamsWorkspace
    when :slack
      ReminderSlackWorkspace
    end
  end

  def self.client_installation_outdated?(client_installation)
    client_installation && !client_installation.events.include?("reminder")
  end

  def this_client_installation(client_app)
    Apps::Internal.integration(client_app)&.installations_on(this_organization)&.first
  end

  def outdated_slack_installation_warning
    slack_installation = this_client_installation(:slack)
    if Orgs::RemindersHelper.client_installation_outdated?(slack_installation)
      render "orgs/reminders/outdated", client_installation: slack_installation, client_name: ReminderSlackWorkspace.alt_name, client_class: ReminderSlackWorkspace.name, hidden: false
    end
  end

  # This method's main purpose is to render warning messages with links to action(in most cases link to documentation) that user can take
  # for the client platform selected(msteams/slack) in the following three cases:
  # Case 1: The selected client platform is not installed for the org
  # Case 2: The selected client platform installation is outdated, i.e. reminder event is not subscribed
  # Case 3: The selected client platform does not have any workspace connected (currently such a
  #         message is only required for MS Teams, as user has to perform actions outside of dotcom to add new workspaces)
  def client_outdated_or_not_installed_message(client_app: :slack, hidden: true,  client_workspace_configured: true)
    reminder_client_workpace_class = Orgs::RemindersHelper.client_to_workspace_mapping(client_app)
    client_installation = this_client_installation(client_app)
    if client_installation.nil?
      render "orgs/reminders/not_installed", installation_target: Apps::Internal.integration(client_app), client_name: reminder_client_workpace_class.alt_name, client_class: reminder_client_workpace_class.name, hidden: hidden
    elsif Orgs::RemindersHelper.client_installation_outdated?(client_installation)
      render "orgs/reminders/outdated", client_installation: client_installation, client_name: reminder_client_workpace_class.alt_name, client_class: reminder_client_workpace_class.name, hidden: hidden
    elsif !client_workspace_configured
      render "orgs/reminders/workspace_not_configured", client_installation: client_installation, client_name: reminder_client_workpace_class.alt_name, client_class: reminder_client_workpace_class.name, hidden: hidden
    end
  end
end
