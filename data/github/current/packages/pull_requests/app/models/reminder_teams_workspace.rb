# typed: true
# frozen_string_literal: true

class ReminderTeamsWorkspace < ReminderClientWorkspace
  include ReminderTeamsChannel

  # Since MS teams for personal scope is not bound by a workspace id, hence keeping a common id for personal scope
  PERSONAL_REMINDER_TEAMS_ID = "591fc239-1446-4a3a".freeze

  alias_attribute :teams_id, :slack_id

  def validate_and_post_message(actor, reminder_url, reminder)
    validate_and_post_message_to_teams(actor, reminder_url, reminder)
  end

  def self.create_or_update_workspace(name:, remindable:, teams_id:)
    create_or_update_workspace_for_type(name: name, remindable: remindable, client_id: teams_id, type: self.name)
  end

  def self.image_url
    "modules/site/integrators/microsoftteams.png"
  end

  def self.alt_name
    "Microsoft Teams"
  end
end
