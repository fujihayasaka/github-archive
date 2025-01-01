# typed: true
# frozen_string_literal: true

require "test_helper"

class CacheSyncEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
    @updates = [
      { action: :synced,  repository_id: @repo.id },
    ]
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::CacheSyncEvent, :repository_id
    assert_event_required_attributes Hook::Event::CacheSyncEvent, :cache_location
    assert_event_required_attributes Hook::Event::CacheSyncEvent, :ref_update
  end

  test "returns the correct repository" do
    event = Hook::Event::CacheSyncEvent.new(
      repository_id: @repo.id,
      cache_location: "pluto",
      ref_update: { "ref": "refs/heads/develop", "before": "0000000000000000000000000000000000000000", "after": "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24" }
    )
    assert_equal @repo, event.repository
  end
end
