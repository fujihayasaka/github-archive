# typed: true
# frozen_string_literal: true

class ReminderSlackWorkspace < ReminderClientWorkspace
  include ReminderSlackChannel

  def validate_and_post_message(actor, reminder_url, reminder)
    validate_and_post_message_to_slack(actor, reminder_url, reminder)
  end

  def self.create_or_update_workspace(name:, remindable:, slack_id:)
    create_or_update_workspace_for_type(name: name, remindable: remindable, client_id: slack_id, type: self.name)
  end

  def self.image_url
    "modules/site/integrators/slackhq.png"
  end

  def self.alt_name
    "Slack"
  end
end
