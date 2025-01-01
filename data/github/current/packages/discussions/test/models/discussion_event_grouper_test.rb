# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionEventGrouperTest < GitHub::TestCase
  context "#group_events" do
    test "groups mark + unmark answer events by actor and comment" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 1)
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_equal 1, groups.size
      assert_equal events, groups.first.events
      assert_empty grouper.ungrouped_events
    end

    test "groups locked + unlocked events by actor" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "locked")
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "unlocked")
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_equal 1, groups.size
      assert_equal events, groups.first.events
      assert_empty grouper.ungrouped_events
    end

    test "does not group locked + unlocked events when actor differs" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "locked")
      event2 = build(:discussion_event, created_at: now, actor_id: 2,
        event_type: "unlocked")
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group locked + unlocked events when time differs too much" do
      past_time = (DiscussionEventGrouper::ROLLUP_INTERVAL + 1.hour).ago
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "locked")
      event2 = build(:discussion_event, created_at: past_time, actor_id: 1,
        event_type: "unlocked")
      events = [event2, event1]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group mark + unmark answer events when comment differs" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 2)
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group locked + locked events" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "locked")
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "locked")
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group unlocked + unlocked events" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "unlocked")
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "unlocked")
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group mark + mark answer events" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1)
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group unmark + unmark answer events" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 1)
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group marked answer + locked events" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "locked")
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group marked answer + unlocked events" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "unlocked")
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group unmarked answer + locked events" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "locked")
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group unmarked answer + unlocked events" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "unlocked")
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group mark + unmark answer events when time differs too much" do
      past_time = (DiscussionEventGrouper::ROLLUP_INTERVAL + 1.hour).ago
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: past_time, actor_id: 1,
        event_type: "answer_marked", comment_id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 1)
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "does not group mark + unmark answer events when actor differs" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 2,
        event_type: "answer_unmarked", comment_id: 1)
      events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "creates two groups for mark/unmark events that have an event created between them" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1, id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 1, id: 2)
      event3 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 2, id: 3)
      event4 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1, id: 4)
      event5 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 1, id: 5)
      events = [event1, event2, event3, event4, event5]
      events_group1 = [event1, event2]
      events_group2 = [event4, event5]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_equal 2, groups.size
      assert_equal events_group1, groups.first.events
      assert_equal events_group2, groups.second.events
      assert_equal grouper.ungrouped_events, [event3]
    end

    test "creates groups with a maximum of 2 events" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1, id: 1)
      event2 = build(:discussion_event, created_at: now + 1.second, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 1, id: 2)
      event3 = build(:discussion_event, created_at: now + 2.seconds, actor_id: 1,
        event_type: "answer_marked", comment_id: 1, id: 3)
      events = [event1, event2, event3]
      result_events = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_equal 1, groups.size
      assert_equal result_events, groups.first.events
      assert_equal [event3], grouper.ungrouped_events
    end

    test "does not groups events that have an incorrect event type" do
      now = Time.zone.now
      event1 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_unmarked", comment_id: 1, id: 1)
      event2 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1, id: 2)
      event3 = build(:discussion_event, created_at: now, actor_id: 1,
        event_type: "answer_marked", comment_id: 1, id: 3)
      events = [event1, event2, event3]
      event_results = [event1, event2]
      grouper = DiscussionEventGrouper.new(events)

      groups = grouper.group_events

      assert_equal 1, groups.size
      assert_equal event_results, groups.first.events
      assert_equal [event3], grouper.ungrouped_events
    end
  end
end
