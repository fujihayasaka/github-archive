# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimelineHiddenItemsTest < GitHub::TestCase
  context ".to_cursor" do
    test "returns the same string when passed a string" do
      assert_equal "real-cursor", DiscussionTimelineHiddenItems.to_cursor("real-cursor")
    end

    test "returns the global_relay_id when passed a model instance" do
      record = build_stubbed(:user)
      assert_equal record.global_relay_id, DiscussionTimelineHiddenItems.to_cursor(record)
    end

    test "returns the global_relay_id of first event when passed anything else" do
      record = build_stubbed(:user)
      other_record = build_stubbed(:user)

      DiscussionEventGroup.new([record, other_record])

      assert_equal record.global_relay_id, DiscussionTimelineHiddenItems.to_cursor(record)
    end
  end

  test "turns passed in before/after values into cursors" do
    repository = create(:repository, has_discussions: true)
    discussion = create(:discussion, repository: repository)
    before = build_stubbed(:discussion_comment, discussion: discussion, repository: repository)
    after = build_stubbed(:discussion_comment, discussion: discussion, repository: repository)
    hidden_items = DiscussionTimelineHiddenItems.new(0, before: before, after: after)

    assert_equal before.global_relay_id, hidden_items.before_cursor
    assert_equal after.global_relay_id, hidden_items.after_cursor
  end
end
