# typed: true
# frozen_string_literal: true

class DiscussionEventGroup
  extend T::Sig

  attr_reader :events

  sig { params(events: T.untyped).void }
  def initialize(events)
    @events = events.sort_by(&:created_at)
  end

  sig { returns(T.untyped) }
  def hash
    events.hash
  end

  sig { params(other: T.untyped).returns(T.untyped) }
  def ==(other)
    other.is_a?(DiscussionEventGroup) && events == other.events
  end
  alias_method :eql?, :==

  sig { returns(T.untyped) }
  def earliest_event
    events.first
  end

  sig { returns(T.untyped) }
  def latest_event
    events.last
  end

  # Pull event type and comment from the last event since it's the event that
  # represents the ending state
  delegate :event_type, :comment_author, :comment_id, :locked?,
    :unlocked?, :marked_or_unmarked_answer?, :created_at,
    :id, :safe_actor, to: :latest_event

  delegate :size, to: :events

  sig { returns(T.untyped) }
  def event_ids
    @event_ids ||= Set.new(events.map(&:id))
  end
end
