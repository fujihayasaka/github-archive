# typed: true
# frozen_string_literal: true

class Issue::Adapter::UnlockedEventAdapter < Issue::Adapter::IssueEventAdapter
  UNLOCKED_EVENT = "UnlockedEvent"

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: UNLOCKED_EVENT)
  end
end
