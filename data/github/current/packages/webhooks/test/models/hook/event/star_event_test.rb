# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventStarEventTest < GitHub::TestCase
  include HookEventTestHelper
  extend T::Helpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository)

    @event_attrs = {
      user_id: @user.id,
      starred_id: @repo.id,
      action: :created,
    }
  end

  test "required attributes" do
    T.unsafe(self).assert_event_required_attributes(Hook::Event::StarEvent, *@event_attrs.keys)
  end

  context "#actor" do
    test "is the user who did the starring" do
      event = Hook::Event::StarEvent.new(@event_attrs)
      assert_equal @user, event.actor
    end
  end

  context "#target_repository" do
    test "is the starred repo" do
      event = Hook::Event::StarEvent.new(@event_attrs)
      assert_equal @repo, event.target_repository
    end
  end
end
