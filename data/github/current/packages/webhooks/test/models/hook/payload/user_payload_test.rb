# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadUserPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @actor = create(:user)
  end

  context "when a user is created" do
    test "payload is complete" do
      event = Hook::Event::UserEvent.new(
          user_id: @user.id,
          action: :created,
          actor_id: @actor.id,
      )
      payload = Hook::Payload::UserPayload.new(event).to_hash
      assert_equal :created, payload[:action]
      assert_equal @user.login, payload[:user][:login]
      assert_equal @actor.login, payload[:sender][:login]
    end
  end
end
