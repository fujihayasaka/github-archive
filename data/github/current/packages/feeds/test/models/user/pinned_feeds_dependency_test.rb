# typed: true
# frozen_string_literal: true

require "test_helper"

class UserPinnedFeedsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  test "pins feed" do
    topic = create(:topic)
    assert_difference("PinnedFeed.count", 1) do
      @user.pin_feed(topic)
    end
  end

  test "unpins feed" do
    pinned_feed = create(:pinned_feed, user: @user)
    assert_difference("PinnedFeed.count", -1) do
      @user.unpin_feed(pinned_feed)
    end
  end
end
