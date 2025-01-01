# typed: true
# frozen_string_literal: true

module Reminders
  class AddReminderForSlackChannelJob < RealTimeJob
    # Currently it takes around 10 seconds on Slack Integrations' side for some big organisations
    # We don't know p95 or average here because the amount of requests is very low
    # To account for even bigger orgs it's safe to assume that 15 seconds should be enough
    HTTP_TIMEOUT_IN_SECONDS = 30

    resolve_tenant_context do |kwargs|
      Reminder.find_by(id: kwargs[:reminder_id])&.remindable&.business
    end

    def perform(actor_id:, action:, reminder_url:, reminder_id:)
      with_write do
        actor = User.find_by(id: actor_id)
        return unless actor

        reminder = Reminder.find_by(id: reminder_id)
        return unless reminder

        success, response = SlackApi.post_reminder_change_to_channel(
          reminder_url: reminder_url,
          reminder: reminder,
          user: actor,
          action: action,
          timeout: HTTP_TIMEOUT_IN_SECONDS
        )

        error = response.try(:dig, "error")

        # slack integration returns a 200 even if there is an error, error is passed in a response body
        if !success || error.present?
          GitHub.logger.error(
            "Error adding reminder to Slack channel in async mode",
            fn: "AddReminderForSlackChannelJob.perform",
            error_message: error,
            actor_id: actor.id,
            action: action,
            organization: reminder.remindable&.name
          )
          reminder.destroy!
          return false
        end

        GitHub.logger.info(
          "Reminder for Slack channel has been added in async mode",
          fn: "AddReminderForSlackChannelJob.perform",
          actor_id: actor.id,
          action: action,
          organization: reminder.remindable&.name
        )
        reminder.slack_channel_id = response["channel"]
        reminder.save!
      end
    end
  end
end
