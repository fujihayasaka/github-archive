# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadEnterprisePayloadTest < GitHub::TestCase
  fixtures do
    @user = create :user
  end

  test "v3" do
    event = Hook::Event::EnterpriseEvent.new(
      action: :test,
      actor_id: @user.id,
    )

    payload = Hook::Payload::EnterprisePayload.new(event)

    v3 = payload.to_hash

    assert_equal :test, v3[:action]
    assert_equal @user.login, v3[:sender][:login]
  end
end
