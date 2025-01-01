# typed: true
# frozen_string_literal: true

require "test_helper"

class PinnedFeedTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  test "belongs to a user" do
    feed = create(:pinned_feed, user: @user)
    assert_equal @user, feed.user
  end

  test "belongs to a topic" do
    topic = create(:topic)
    feed = create(:pinned_feed, topic: topic)
    assert_equal topic, feed.topic
  end

  test "display name is topic name" do
    feed = create(:pinned_feed)
    assert_equal feed.topic.name, feed.display_name
  end
end
