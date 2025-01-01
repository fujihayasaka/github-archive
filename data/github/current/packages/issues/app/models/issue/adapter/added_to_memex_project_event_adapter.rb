# typed: true
# frozen_string_literal: true

class Issue::Adapter::AddedToMemexProjectEventAdapter < Issue::Adapter::MemexProjectEventAdapter
  TYPES = [
    PlatformTypes::AddedToProjectV2Event
  ].freeze

  ADDED_TO_MEMEX_PROJECT_EVENT = "AddedToProjectV2Event"

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: ADDED_TO_MEMEX_PROJECT_EVENT)
  end
end
