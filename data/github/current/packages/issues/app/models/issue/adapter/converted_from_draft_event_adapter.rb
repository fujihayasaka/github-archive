# typed: true
# frozen_string_literal: true

class Issue::Adapter::ConvertedFromDraftEventAdapter < Issue::Adapter::TimelineEventAdapter
  CONVERTED_FROM_DRAFT_EVENT = "ConvertedFromDraftEvent"
  EVENT_NAME = CONVERTED_FROM_DRAFT_EVENT.chomp("Event").underscore

  attr_reader :id, :actor

  def initialize(context, event)
    super(context)
    @event = event
    @id = event.id
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
end
