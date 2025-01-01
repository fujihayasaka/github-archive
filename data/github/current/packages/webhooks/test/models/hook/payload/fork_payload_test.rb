# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadForkPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @parent = create(:repository)
    @fork = create :repository, parent: @parent, owner: @user
  end

  setup do
    @event = Hook::Event::ForkEvent.new fork_repository_id: @fork.id
    @payload = Hook::Payload::ForkPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal @fork.id, v3[:forkee][:id]
    assert_equal @fork.name, v3[:forkee][:name]
    assert_equal true, v3[:forkee][:public]
    assert_equal @user.id, v3[:forkee][:owner][:id]
    assert_equal @parent.id, v3[:repository][:id]
    assert_equal @parent.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.login, v3[:sender][:login]
  end
end
