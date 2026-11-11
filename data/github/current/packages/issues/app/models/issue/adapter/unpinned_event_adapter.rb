# typed: true
# frozen_string_literal: true

class Issue::Adapter::UnpinnedEventAdapter < Issue::Adapter::IssueEventAdapter
  UNPINNED_EVENT = "UnpinnedEvent"

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: UNPINNED_EVENT)
  end
end
