# typed: true
# frozen_string_literal: true

class Issue::Adapter::UserBlockedEventAdapter < Issue::Adapter::IssueEventAdapter
  USER_BLOCKED_EVENT = "UserBlockedEvent"
  DURATION_MAP = Platform::Enums::UserBlockDuration.values.map { |k, v| [v.value, k] }.to_h

  attr_reader :block_duration, :subject

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: USER_BLOCKED_EVENT)

    @block_duration = DURATION_MAP[@issue_event.block_duration_days]

    blocked_user = context.users_by_id[@issue_event.subject_id]
    @subject = blocked_user
  end
end
