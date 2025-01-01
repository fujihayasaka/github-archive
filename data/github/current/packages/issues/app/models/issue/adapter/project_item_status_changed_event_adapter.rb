# typed: true
# frozen_string_literal: true

class Issue::Adapter::ProjectItemStatusChangedEventAdapter < Issue::Adapter::TimelineEventAdapter
  PROJECT_ITEM_STATUS_CHANGED_EVENT = "ProjectV2ItemStatusChangedEvent"
  EVENT_NAME = PROJECT_ITEM_STATUS_CHANGED_EVENT.chomp("Event").underscore

  attr_reader :id, :memex_title, :memex_resource_path, :status, :previous_status, :actor

  def initialize(context, event)
    super(context)
    @event = event
    @id = event.id
    @memex_title = memex.title
    @memex_resource_path = memex.url
    @status = event.status
    @previous_status = event.previous_status
    @actor = @context.users_by_id[event.actor_id]
  end

  def event_name
    EVENT_NAME
  end

  def database_id
    id
  end

  def via_app
    nil
  end

  def created_at
    @event.created_at
  end

  def automated?
    @event.automated?
  end

  def memex
    context.memexes_by_id[@event.memex_id]
  end
end
