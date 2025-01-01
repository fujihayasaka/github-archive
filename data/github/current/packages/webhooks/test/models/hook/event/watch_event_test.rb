# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventWatchEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository)

    @event_attrs = {
      user_id: @user.id,
      starred_type: @repo.class.name,
      starred_id: @repo.id,
    }
  end

  test "required attributes" do
    assert_event_required_attributes(Hook::Event::WatchEvent, :user_id, :starred_id, :starred_type)
  end

  context "#user" do
    test "is found using user_id" do
      event = Hook::Event::WatchEvent.new(@event_attrs)
      assert_equal @user, event.user
    end
  end

  context "#actor" do
    test "is the user who did the starring" do
      event = Hook::Event::WatchEvent.new(@event_attrs)
      assert_equal @user, event.actor
    end
  end

  context "#starred" do
    test "returns the starred repo" do
      event = Hook::Event::WatchEvent.new(@event_attrs)
      assert_equal @repo, event.starred
    end
  end

  context "#target_repository" do
    test "is the starred repo" do
      event = Hook::Event::WatchEvent.new(@event_attrs)
      assert_equal @repo, event.target_repository
    end

    test "returns nil on deleted repository" do
      @repo.remove(@user)
      event = Hook::Event::WatchEvent.new(@event_attrs)
      assert_nil event.target_repository
    end
  end

  context "#deliverable?" do
    test "returns true when repository exist" do
      event = Hook::Event::WatchEvent.new(@event_attrs)
      assert_predicate event, :deliverable?
    end

    test "returns false for a deleted repository" do
      @repo.destroy!
      event = Hook::Event::WatchEvent.new(@event_attrs)
      refute_predicate event, :deliverable?
    end
  end
end
