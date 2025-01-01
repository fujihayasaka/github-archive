# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadStarPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository)
    @star = create(:star)
  end

  setup do
    @event = Hook::Event::StarEvent.new(
      user_id: @user.id,
      starred_id: @repo.id,
      action: :created,
      star_id: @star.id,
    )
    @payload = Hook::Payload::StarPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal :created, v3[:action]
    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.login, v3[:sender][:login]
    assert_equal @star.created_at, v3[:starred_at]
  end

end
