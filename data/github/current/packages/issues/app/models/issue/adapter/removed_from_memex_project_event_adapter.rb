# typed: true
# frozen_string_literal: true

class Issue::Adapter::RemovedFromMemexProjectEventAdapter < Issue::Adapter::MemexProjectEventAdapter
  TYPES = [
    PlatformTypes::RemovedFromProjectV2Event
  ].freeze

  REMOVED_FROM_MEMEX_PROJECT_EVENT = "RemovedFromProjectV2Event"

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: REMOVED_FROM_MEMEX_PROJECT_EVENT)
  end
end
