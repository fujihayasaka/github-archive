# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadPublicPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
  end

  setup do
    @event = Hook::Event::PublicEvent.new repo_id: @repo.id, actor_id: @user.id
    @payload = Hook::Payload::PublicPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.login, v3[:sender][:login]
  end

end
