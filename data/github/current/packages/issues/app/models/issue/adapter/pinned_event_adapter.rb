# typed: true
# frozen_string_literal: true

class Issue::Adapter::PinnedEventAdapter < Issue::Adapter::IssueEventAdapter
  PINNED_EVENT = "PinnedEvent"

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: PINNED_EVENT)
  end
end
