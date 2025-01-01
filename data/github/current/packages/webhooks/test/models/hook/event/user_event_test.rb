# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventUserEventTest < GitHub::TestCase
  include HookEventTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @actor = create(:user)
    @event = Hook::Event::UserEvent.new(
      action: :created,
      user_id: @user.id,
      actor_id: @actor.id,
    )
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::UserEvent, :action, :user_id
  end

  context "#user" do
    test "returns the specified user" do
      assert_equal @user, @event.user
    end
  end

  context "#actor" do
    test "returns the actor" do
      assert_equal @actor, @event.actor
    end

    test "falls back to the Ghost user if no actor is present" do
      event = Hook::Event::UserEvent.new(
        action: :created,
        user_id: @user.id,
        actor_id: nil,
      )

      assert_equal User.ghost, event.actor
    end
  end

  context "#deliverable" do
    test "returns false if the user is not found" do
      event = Hook::Event::UserEvent.new(
          action: :created,
          user_id: -1,
      )
      refute_predicate event, :deliverable?
    end

    test "returns true if the user is found" do
      assert_predicate @event, :deliverable?
    end
  end
end
