# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadDeployKeyPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository)
    @key = create(:public_key, repository: @repo)
  end

  setup do
    @event = Hook::Event::DeployKeyEvent.new(
      actor_id: @user.id,
      repository_id: @repo.id,
      action: :created,
      key_id: @key.id,
    )
    @payload = Hook::Payload::DeployKeyPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal :created, v3[:action]
    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.login, v3[:sender][:login]
    assert_equal @key.id, v3[:key][:id]
    assert_equal @key.key, v3[:key][:key]
  end

end
