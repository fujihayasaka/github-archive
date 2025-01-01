# typed: true
# frozen_string_literal: true

# Public: Used to roll up similar events in a discussion timeline.
class DiscussionEventGrouper
  # Public: Time window in which two similar events must have occurred in
  # order for them to be rolled up together.
  extend T::Sig

  ROLLUP_INTERVAL = 2.hours

  # Public: After running #group_events, this list will contain only
  # events that did not fit into any groups.
  attr_reader :ungrouped_events

  # events - an Array of DiscussionEvent records
  sig { params(events: T.untyped).void }
  def initialize(events)
    @ungrouped_events = events.sort_by(&:created_at).dup
  end

  # Public: Groups the events and returns a list of DiscussionEventGroups.
  sig { returns(T.untyped) }
  def group_events
    groups = event_groups_by_type
    events_that_are_now_in_groups = groups.flat_map(&:events)
    events_that_are_now_in_groups.each do |processed_event|
      ungrouped_events.delete(processed_event)
    end
    groups
  end

  sig { returns(T.untyped) }
  def event_groups_by_type
    groups = []
    return groups if ungrouped_events.empty?

    outer_index = 0
    while outer_index < ungrouped_events.length
      base_event = ungrouped_events[outer_index]

      if !has_been_grouped?(groups, base_event)
        inner_index = outer_index + 1
        group = find_a_group_for(inner_index, base_event, groups)
        groups << group if group.size > 1
      end

      outer_index += 1
    end

    groups
  end

  sig { params(groups: T.untyped, event: T.untyped).returns(T.untyped) }
  def has_been_grouped?(groups, event)
    groups.any? { |group| group.event_ids.include?(event.id) }
  end

  sig { params(index: T.untyped, base_event: T.untyped, groups: T.untyped).returns(T.untyped) }
  def find_a_group_for(index, base_event, groups)
    events_in_group = [base_event]
    previous_event = base_event

    while index < ungrouped_events.size
      other_event = ungrouped_events[index]
      if !has_been_grouped?(groups, other_event)
        if can_be_grouped?(previous_event, other_event, events_in_group)
          events_in_group << other_event
          previous_event = other_event
        else
          break
        end
      end

      index += 1
    end

    DiscussionEventGroup.new(events_in_group)
  end

  sig { params(base_event: T.untyped, other_event: T.untyped, group: T.untyped).returns(T.untyped) }
  def can_be_grouped?(base_event, other_event, group)
    return false unless eligible_same_actor_events?(base_event, other_event)
    return false unless occurred_within_interval?(base_event.created_at, other_event.created_at)
    return false unless group.size < 2
    eligible_lock_unlock_events?(base_event, other_event) ||
      eligible_mark_unmark_events?(base_event, other_event)
  end

  sig { params(event: T.untyped, other_event: T.untyped).returns(T.untyped) }
  def eligible_lock_unlock_events?(event, other_event)
    return true if event.locked? && other_event.unlocked?
    event.unlocked? && other_event.locked?
  end

  sig { params(event: T.untyped, other_event: T.untyped).returns(T.untyped) }
  def eligible_mark_unmark_events?(event, other_event)
    return false unless eligible_same_comment_events?(event, other_event)
    return true if event.answer_marked? && other_event.answer_unmarked?
    event.answer_unmarked? && other_event.answer_marked?
  end

  sig { params(event: T.untyped, other_event: T.untyped).returns(T.untyped) }
  def eligible_same_actor_events?(event, other_event)
    event.actor_id == other_event.actor_id
  end

  sig { params(event: T.untyped, other_event: T.untyped).returns(T.untyped) }
  def eligible_same_comment_events?(event, other_event)
    event.comment_id == other_event.comment_id
  end

  sig { params(first_timestamp: T.untyped, second_timestamp: T.untyped).returns(T.untyped) }
  def occurred_within_interval?(first_timestamp, second_timestamp)
    diff = (second_timestamp - first_timestamp).abs
    diff <= ROLLUP_INTERVAL
  end
end
