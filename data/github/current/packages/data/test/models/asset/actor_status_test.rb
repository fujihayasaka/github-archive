# typed: true
# frozen_string_literal: true

require "test_helper"

class AssetActorStatusTest < GitHub::TestCase
  context "validations" do
    test "owner required" do
      status = Asset::ActorStatus.new(actor: create(:user))
      refute status.valid?
      assert_equal ["can't be blank"], status.errors[:owner_id]
    end

    test "actor required" do
      status = Asset::ActorStatus.new(owner: create(:user))
      refute status.valid?
      assert_equal ["can't be blank"], status.errors[:actor_id]
    end

    test "bandwith_up is positive" do
      user = create(:user)
      status = Asset::ActorStatus.new(bandwidth_up: -1,
        owner: user, actor: user)
      refute status.valid?
      assert_equal ["must be greater than or equal to 0.0"],
        status.errors[:bandwidth_up]
    end

    test "bandwith_down is positive" do
      user = create(:user)
      status = Asset::ActorStatus.new(bandwidth_down: -1,
        owner: user, actor: user)
      refute status.valid?
      assert_equal ["must be greater than or equal to 0.0"],
        status.errors[:bandwidth_down]
    end
  end

  test "#reset" do
    user = create(:user)
    status = Asset::ActorStatus.new(bandwidth_up: 10.0,
      bandwidth_down: 20.0, owner: user, actor: user)
    status.reset
    assert_equal 0.0, status.bandwidth_up
    assert_equal 0.0, status.bandwidth_down
  end

  test "#rebuild for users" do
    Timecop.freeze(Time.utc(2015, 1, 1, 12)) do
      user = create(:user)
      repo = create(:repository)
      create(:asset_status, owner: user)
      bandwidth = 0.125
      Asset::ActorActivity.create(bandwidth_up: 0,
                                  bandwidth_down: bandwidth,
                                  owner_id: user,
                                  actor_id: user,
                                  key_id: 0,
                                  repository: repo,
                                  activity_started_at: 1.hour.ago.utc,
                                  asset_type: :lfs)
      Asset::ActorActivity.create(bandwidth_up: bandwidth,
                                  bandwidth_down: bandwidth,
                                  owner_id: user,
                                  actor_id: user,
                                  key_id: 0,
                                  repository: repo,
                                  activity_started_at: 30.minutes.ago.utc,
                                  asset_type: :registry)
      status = Asset::ActorStatus.create(owner: user, actor: user, key_id: 0)
      status.rebuild

      assert_equal bandwidth, status.reload.bandwidth_down
      assert_equal 0, status.reload.bandwidth_up
    end
  end

  test "#rebuild for keys" do
    Timecop.freeze(Time.utc(2015, 1, 1, 12)) do
      user = create(:user)
      repo = create(:repository)
      key = create(:public_key, repository: repo)
      create(:asset_status, owner: user)
      bandwidth = 0.125
      Asset::ActorActivity.create(bandwidth_up: 0,
                                  bandwidth_down: bandwidth,
                                  owner_id: user,
                                  actor_id: 0,
                                  key: key,
                                  repository: repo,
                                  activity_started_at: 1.hour.ago.utc,
                                  asset_type: :lfs)
      Asset::ActorActivity.create(bandwidth_up: bandwidth,
                                  bandwidth_down: bandwidth,
                                  owner_id: user,
                                  actor_id: 0,
                                  key: key,
                                  repository: repo,
                                  activity_started_at: 30.minutes.ago.utc,
                                  asset_type: :registry)
      status = Asset::ActorStatus.create(owner: user, key: key, actor_id: 0)
      status.rebuild

      assert_equal bandwidth, status.reload.bandwidth_down
      assert_equal 0, status.reload.bandwidth_up
    end
  end

  test "#rebuild with different repos" do
    Timecop.freeze(Time.utc(2015, 1, 1, 12)) do
      user = create(:user)
      repo1 = create(:repository)
      repo2 = create(:repository)
      create(:asset_status, owner: user)
      bandwidth = 0.125
      Asset::ActorActivity.create(bandwidth_up: 0,
                                  bandwidth_down: bandwidth,
                                  owner_id: user,
                                  actor_id: user,
                                  repository: repo1,
                                  activity_started_at: 1.hour.ago.utc,
                                  asset_type: :lfs)
      Asset::ActorActivity.create(bandwidth_up: bandwidth,
                                  bandwidth_down: bandwidth,
                                  owner_id: user,
                                  actor_id: user,
                                  repository: repo2,
                                  activity_started_at: 30.minutes.ago.utc,
                                  asset_type: :lfs)
      status = Asset::ActorStatus.create(owner: user, actor: user)
      status.rebuild

      assert_equal 2 * bandwidth, status.reload.bandwidth_down
      assert_equal bandwidth, status.reload.bandwidth_up
    end
  end

  test "#rebuild with multiple entries and keys" do
    Timecop.freeze(Time.utc(2015, 1, 1, 12)) do
      user = create(:user)
      repo = create(:repository)
      key = create(:public_key, repository: repo)
      create(:asset_status, owner: user)
      bandwidth = 0.125
      Asset::ActorActivity.create(bandwidth_up: 0,
                                  bandwidth_down: bandwidth,
                                  owner_id: user,
                                  actor_id: 0,
                                  key: key,
                                  repository: repo,
                                  activity_started_at: 1.hour.ago.utc,
                                  asset_type: :lfs)
      Asset::ActorActivity.create(bandwidth_up: bandwidth,
                                  bandwidth_down: bandwidth,
                                  owner_id: user,
                                  actor_id: 0,
                                  key: key,
                                  repository: repo,
                                  activity_started_at: 30.minutes.ago.utc,
                                  asset_type: :lfs)
      status = Asset::ActorStatus.create(owner: user, key: key, actor_id: 0)
      status.rebuild

      assert_equal 2 * bandwidth, status.reload.bandwidth_down
      assert_equal bandwidth, status.reload.bandwidth_up
    end
  end

  test "#rebuild with no current data" do
    Timecop.freeze(Time.utc(2015, 1, 1, 12)) do
      user = create(:user)
      repo = create(:repository)
      create(:asset_status, owner: user)
      bandwidth = 0.125
      Asset::ActorActivity.create(bandwidth_up: 0,
                                  bandwidth_down: bandwidth,
                                  owner_id: user,
                                  actor_id: user,
                                  repository: repo,
                                  activity_started_at: 45.days.ago.utc,
                                  asset_type: :lfs)
      Asset::ActorActivity.create(bandwidth_up: bandwidth,
                                  bandwidth_down: bandwidth,
                                  owner_id: user,
                                  actor_id: user,
                                  repository: repo,
                                  activity_started_at: 60.days.ago.utc,
                                  asset_type: :registry)

      status = Asset::ActorStatus.create(owner: user, actor: user)
      status.rebuild

      assert_equal 0, status.reload.bandwidth_down
      assert_equal 0, status.reload.bandwidth_up
    end
  end
end
