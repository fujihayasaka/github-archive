# typed: true
# frozen_string_literal: true

require "test_helper"

class PlaceholdersTest < GitHub::TestCase
  fixtures do
    @issue = create(:issue)
    @memex = create(:memex_project)
    @user = create(:user)
  end

  context "MemexProjectEvent" do
    test "async_actor returns actor" do
      event = Timeline::Placeholder::MemexProjectEvent.new(id: 1234, issue_id: @issue.id, sort_datetimes: [], memex_id: @memex.id, was_automated: false, actor_id: @user.id, created_at: Time.now)
      assert_equal @user, event.async_actor.sync
    end

    test "async_actor returns nil if actor is destroyed" do
      @user.destroy
      event = Timeline::Placeholder::MemexProjectEvent.new(id: 1234, issue_id: @issue.id, sort_datetimes: [], memex_id: @memex.id, was_automated: false, actor_id: @user.id, created_at: Time.now)
      assert_nil event.async_actor.sync
    end

    test "async_actor is batching request to fetch actors" do
      actors = []
      promises = []
      events = []

      5.times do
        actor = create(:user)

        events << Timeline::Placeholder::MemexProjectEvent.new(id: 1234, issue_id: @issue.id, sort_datetimes: [], memex_id: @memex.id, was_automated: false, actor_id: actor.id, created_at: Time.now)
        actors << actor
      end

      async_actors = assert_query_count_per_table({ users: 1 }) do
        Promise.all(events.map(&:async_actor)).sync
      end

      assert_same_elements actors, async_actors
    end
  end
end
