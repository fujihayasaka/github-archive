# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadCacheSyncPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository)
    @ref_update = { "ref": "refs/heads/develop", "before": "0000000000000000000000000000000000000000", "after": "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24" }
    @cache_location = "antarctica"
  end

  setup do
    @event = Hook::Event::CacheSyncEvent.new(
      repository_id: @repo.id,
      cache_location: @cache_location,
      ref_update: @ref_update,
    )
    @payload = Hook::Payload::CacheSyncPayload.new @event
  end

  test "correct payload" do
    ph = @payload.to_hash

    assert_equal @repo.id, ph[:repository][:id]
    assert_equal @repo.name, ph[:repository][:name]
    assert_equal @cache_location, ph[:cache_location]
    assert_equal @ref_update[:ref], ph[:ref]
    assert_equal @ref_update[:before], ph[:before]
    assert_equal @ref_update[:after], ph[:after]
  end
end
