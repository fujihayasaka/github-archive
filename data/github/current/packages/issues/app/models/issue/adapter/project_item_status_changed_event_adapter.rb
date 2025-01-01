# typed: true
# frozen_string_literal: true

class Issue::Adapter::ProjectItemStatusChangedEventAdapter < Issue::Adapter::MemexProjectEventAdapter
  TYPES = [
    PlatformTypes::ProjectV2ItemStatusChangedEvent
  ].freeze

  attr_reader :status, :previous_status

  PROJECT_ITEM_STATUS_CHANGED_EVENT = "ProjectV2ItemStatusChangedEvent"

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: PROJECT_ITEM_STATUS_CHANGED_EVENT)

    @status = @issue_event.project_status
    @previous_status = @issue_event.project_previous_status
  end
end
