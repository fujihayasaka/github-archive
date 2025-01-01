# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionEventGroupTest < GitHub::TestCase
  context "#==" do
    test "groups are equal when they have the same events" do
      event1 = build(:discussion_event)
      event2 = build(:discussion_event)

      group1 = DiscussionEventGroup.new([event1])
      group2 = DiscussionEventGroup.new([event1])
      group3 = DiscussionEventGroup.new([event2])

      assert_equal group1, group2
      refute_equal group1, group3
      refute_equal group2, group3
    end
  end

  context "#event_type" do
    test "returns event_type from latest event" do
      earliest_event = build(:discussion_event, created_at: 1.year.ago,
        event_type: "answer_marked")
      latest_event = build(:discussion_event, created_at: 1.minute.ago,
        event_type: "answer_unmarked")

      group = DiscussionEventGroup.new([latest_event, earliest_event])

      assert_equal "answer_unmarked", group.event_type
    end
  end
end
