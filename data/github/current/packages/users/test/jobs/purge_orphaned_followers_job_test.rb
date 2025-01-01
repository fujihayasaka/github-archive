# typed: true
# frozen_string_literal: true

require "test_helper"

class PurgeOrphanedFollowersJobTest < GitHub::TestCase
  fixtures do
    @existent_follower = create(:user)
    @existent_followee = create(:user)
    @ephemeral_follower = create(:user)
    @ephemeral_followee = create(:user)

    @non_orphan = create(:following, user: @existent_follower, following: @existent_followee)
    @orphan_follower = create(:following, user: @ephemeral_follower, following: @existent_followee)
    @orphan_followee = create(:following, user: @existent_follower, following: @ephemeral_followee)
    @orphan_both = create(:following, user: @ephemeral_follower, following: @ephemeral_followee)
  end

  test "purges followers records that are associated with users that no longer exist" do
    @ephemeral_follower.delete
    @ephemeral_followee.delete

    refute_nil @non_orphan.reload
    refute_nil Following.find_by(id: @orphan_follower.id)
    refute_nil Following.find_by(id: @orphan_followee.id)
    refute_nil Following.find_by(id: @orphan_both.id)

    PurgeOrphanedFollowersJob.perform_now

    refute_nil @non_orphan.reload
    assert_nil Following.find_by(id: @orphan_follower.id)
    assert_nil Following.find_by(id: @orphan_followee.id)
    assert_nil Following.find_by(id: @orphan_both.id)
  end

  test "works on multi tenant enterprise, ignores tenant scoping" do
    on_multi_tenant_enterprise do
      existent_followee = create :emu
      ephemeral_follower = create :emu

      orphan_following = create :following, user: ephemeral_follower, following: existent_followee
      ephemeral_follower.delete
      refute_nil Following.find_by(id: orphan_following.id)

      # Ensure we don't accidentally get a false positive. unset the current tenant
      # before running the job
      GitHub::CurrentTenant.remove

      PurgeOrphanedFollowersJob.perform_now
      assert_nil Following.find_by(id: orphan_following.id)
    end
  end
end
