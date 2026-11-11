# typed: true
# frozen_string_literal: true

module ReminderTeamsChannel
  extend ActiveSupport::Concern

  def validate_and_post_message_to_teams(actor, reminder_url, reminder)
    #code to push message to teams and channel id to the reminder entry
  end
end
