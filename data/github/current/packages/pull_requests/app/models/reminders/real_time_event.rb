# typed: true
# frozen_string_literal: true

module Reminders
  class RealTimeEvent
    attr_reader :actor, :context, :pull_request_ids, :reminder, :repository_id, :subject, :type
    def initialize(actor:, context:, type:, pull_request_ids:, reminder:, repository_id:, subject: nil)
      @actor = actor
      @context = context
      @type = type
      @pull_request_ids = pull_request_ids
      @reminder = reminder
      @repository_id = repository_id
      @subject = subject

      unless ReminderEventSubscription.event_types.key?(type)
        raise ArgumentError, "Invalid event type: #{type.inspect}"
      end
    end

    def permitted?
      reminder.permitted_to_repository_id?(repository_id)
    end

    def dedup_key
      [
        recipient_id,
        subject&.to_global_id,
      ].join("-")
    end

    private def recipient_id
      case reminder
      when Reminder then [reminder.slack_channel, reminder.slack_workspace.slack_id].join("-")
      when PersonalReminder then reminder.user_id
      else
        raise "Unknown reminder type: #{reminder.class.name}"
      end
    end
  end
end
