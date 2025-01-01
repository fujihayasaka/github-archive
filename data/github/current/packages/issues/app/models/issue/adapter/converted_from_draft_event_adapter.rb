# typed: true
# frozen_string_literal: true

class Issue::Adapter::ConvertedFromDraftEventAdapter < Issue::Adapter::MemexProjectEventAdapter
  TYPES = [
    PlatformTypes::ConvertedFromDraftEvent
  ].freeze

  CONVERTED_FROM_DRAFT_EVENT = "ConvertedFromDraftEvent"

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: CONVERTED_FROM_DRAFT_EVENT)
  end
end
