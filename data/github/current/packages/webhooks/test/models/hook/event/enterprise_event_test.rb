# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventEnterpriseEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create :user
  end

  context "#action" do
    test "is required" do
      assert_event_required_attributes Hook::Event::EnterpriseEvent, :action
    end
  end

  context "#actor_id" do
    test "is required" do
      assert_event_required_attributes Hook::Event::EnterpriseEvent, :actor_id
    end
  end

  context "#actor" do
    test "is looked up using the actor_id" do
      event = Hook::Event::EnterpriseEvent.new(
        action:         :test,
        actor_id:       @user.id,
      )

      assert_equal @user, event.actor
    end
  end
end
