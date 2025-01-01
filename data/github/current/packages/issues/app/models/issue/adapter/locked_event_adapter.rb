# typed: true
# frozen_string_literal: true

class Issue::Adapter::LockedEventAdapter < Issue::Adapter::IssueEventAdapter
  LOCKED_EVENT = "LockedEvent"

  attr_reader :lock_reason

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: LOCKED_EVENT)
    @lock_reason = @issue_event.lock_reason
  end
end
