# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadWatchPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository)
  end

  setup do
    @event = Hook::Event::WatchEvent.new user_id: @user.id, starred_type: @repo.class.name, starred_id: @repo.id
    @payload = Hook::Payload::WatchPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal :started, v3[:action]
    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.login, v3[:sender][:login]
  end

end
