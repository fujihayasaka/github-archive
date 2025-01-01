# typed: true
# frozen_string_literal: true

module Reminders
  class PersonalReminderViewModel
    # List of personal reminders for user
    def self.all_for(current_user)
      slack = Apps::Internal.integration(:slack)
      msteams = Apps::Internal.integration(:msteams)
      organizations = current_user.organizations.to_a

      personal_reminders = PersonalReminder.where(user: current_user, remindable: organizations).includes(:delivery_times, { remindable: :slack_workspace })
      personal_reminders_by_remindable = personal_reminders.index_by(&:remindable)

      slack_installations_by_target = IntegrationInstallation.where(target: organizations, integration: slack).index_by(&:target)
      msteams_installations_by_target = IntegrationInstallation.where(target: organizations, integration: msteams).index_by(&:target)

      organizations.sort_by(&:display_login).map do |organization|
        new(
          current_user: current_user,
          organization: organization,
          personal_reminder: personal_reminders_by_remindable[organization],
          slack_installation: slack_installations_by_target[organization],
          msteams_installation: msteams_installations_by_target[organization]
        )
      end
    end

    # List of personal reminders for user divided by type: configured, available and unavailable
    def self.all_by_type_for(current_user)
      slack = Apps::Internal.integration(:slack)
      msteams = Apps::Internal.integration(:msteams)
      organizations = current_user.organizations.to_a

      personal_reminders = PersonalReminder.where(user: current_user, remindable: organizations).includes(:delivery_times, { remindable: :slack_workspace })
      personal_reminders_by_remindable = personal_reminders.index_by(&:remindable)

      slack_installations_by_target = IntegrationInstallation.where(target: organizations, integration: slack).index_by(&:target)
      msteams_installations_by_target = IntegrationInstallation.where(target: organizations, integration: msteams).index_by(&:target)

      reminders_by_type = { configured: [], available: [], unavailable: [] }
      organizations.sort_by(&:display_login).reduce(reminders_by_type) do |reminders, organization|
        reminder = new(
          current_user: current_user,
          organization: organization,
          personal_reminder: personal_reminders_by_remindable[organization],
          slack_installation: slack_installations_by_target[organization],
          msteams_installation: msteams_installations_by_target[organization]
        )
        if reminder.editable && reminder.configured? && !reminder.ms_teams?
          reminders[:configured] << reminder
        elsif reminder.editable
          reminders[:available] << reminder
        else
          reminders[:unavailable] << reminder
        end
        reminders
      end
    end

    delegate :slack_workspace, to: :personal_reminder, allow_nil: true
    delegate :ms_teams?, to: :personal_reminder, allow_nil: true

    attr_reader :current_user, :organization, :personal_reminder, :slack_installation, :msteams_installation,
                :editable
    def initialize(current_user:, organization:, personal_reminder:, slack_installation:, msteams_installation:)
      @current_user = current_user
      @organization = organization
      @personal_reminder = personal_reminder
      @slack_installation = slack_installation
      @msteams_installation = msteams_installation
      @editable = editable_hint.nil?
    end

    alias_method :editable?, :editable

    def configured?
      personal_reminder&.persisted?
    end

    def editable_hint
      if GitHub.flipper[:notifications_new_scheduled_reminders_view].enabled?(current_user)
        return if organization.adminable_by?(current_user)

        installations = [slack_installation]
        installations += [msteams_installation] if GitHub.flipper[:scheduled_reminders_ms_teams].enabled?(organization)
        hint_message = editable_hint_helper(installations)
        return hint_message unless hint_message.nil?

        if slack_workspaces.empty?
          "No Slack workspace connected"
        end
      else
        return if organization.adminable_by?(current_user)

        if GitHub.flipper[:scheduled_reminders_ms_teams].enabled?(organization)
          hint_message = editable_hint_helper([slack_installation, msteams_installation])
          unless hint_message.nil?
            return hint_message % ["Slack integration or Microsoft Teams integration", organization.display_login]
          end
        else
          hint_message = editable_hint_helper([slack_installation])
          unless hint_message.nil?
            return hint_message % ["Slack integration", organization.display_login]
          end
        end
        if slack_workspaces.empty?
          "To use scheduled reminders, an organization owner needs to connect to a Slack workspace."
        end
      end
    end

    def description
      return unless personal_reminder

      if personal_reminder.delivery_times_text
        "#{personal_reminder.slack_workspace.name} · #{personal_reminder.delivery_times_text}"
      else
        personal_reminder.slack_workspace.name
      end
    end

    private

    def editable_hint_helper(installations)
      if GitHub.flipper[:notifications_new_scheduled_reminders_view].enabled?(current_user)
        if installations.reduce(true) { |result, installation| result &&= installation.nil? }
          "Needs installing"
        elsif installations.reduce(true) { |result, installation| result &&= Orgs::RemindersHelper.client_installation_outdated?(installation) }
          "Needs updating"
        end
      else
        if installations.reduce(true) { |result, installation| result &&= installation.nil? }
          "To use scheduled reminders, the %s needs to be installed in the %s organization."
        elsif installations.reduce(true) { |result, installation| result &&= Orgs::RemindersHelper.client_installation_outdated?(installation) }
          "To use scheduled reminders, the %s needs to be updated in the %s organization."
        end
      end
    end

    def slack_workspaces
      if GitHub.flipper[:scheduled_reminders_ms_teams].enabled?(organization)
        ReminderClientWorkspace.for_remindable(organization)
      else
        ReminderSlackWorkspace.for_remindable(organization)
      end
    end
  end
end
