# typed: true
# frozen_string_literal: true

require "test_helper"

class AssetActorActivityTest < GitHub::TestCase
  context "validations" do
    test "owner required" do
      status = Asset::ActorActivity.new(actor: create(:user))
      refute status.valid?
      assert_equal ["can't be blank"], status.errors[:owner_id]
    end

    test "actor required" do
      status = Asset::ActorActivity.new(owner: create(:user))
      refute status.valid?
      assert_equal ["can't be blank"], status.errors[:actor_id]
    end

    test "bandwith_up is positive" do
      user = create(:user)
      repo = create(:repository)
      status = Asset::ActorActivity.new(bandwidth_up: -1,
        owner: user, actor: user, repository: repo)
      refute status.valid?
      assert_equal ["must be greater than or equal to 0.0"],
        status.errors[:bandwidth_up]
    end

    test "bandwith_down is positive" do
      user = create(:user)
      repo = create(:repository)
      status = Asset::ActorActivity.new(bandwidth_down: -1,
        owner: user, actor: user, repository: repo)
      refute status.valid?
      assert_equal ["must be greater than or equal to 0.0"],
        status.errors[:bandwidth_down]
    end
  end

  test "tracks bandwidth and byte hours per owner and actor" do
    now = Time.now
    owner = create(:user)
    actor = create(:user)
    repo = create(:repository)
    key = create(:public_key, repository: repo)
    Asset::ActorActivity.track(:lfs, owner.id, actor.id, 0, repo.id, now,
      up: 1.1, down: 2.2)
    Asset::ActorActivity.track(:lfs, owner.id, actor.id, 0, repo.id, now,
      up: 10.1, down: 20.2)
    Asset::ActorActivity.track(:lfs, owner.id, 0, key.id, repo.id, now,
      up: 100.1, down: 200.2)
    Asset::ActorActivity.track(:lfs, owner.id, 0, key.id, repo.id, now,
      up: 1000.1, down: 2000.2)

    assert activity = Asset::ActorActivity.where(owner_id: owner.id, actor_id: actor.id, activity_started_at: now).first
    assert activity, Asset::ActorActivity.fetch_for_owner_actor(:lfs, owner.id, actor.id, 0, now - 1.day.seconds, now + 1.day.seconds).first
    assert_equal 11.2, T.must(activity).bandwidth_up, activity.inspect
    assert_equal 22.4, T.must(activity).bandwidth_down, activity.inspect

    assert activity = Asset::ActorActivity.where(owner_id: owner.id, key_id: key.id, activity_started_at: now).first
    assert activity, Asset::ActorActivity.fetch_for_owner_actor(:lfs, owner.id, 0, key.id, now - 1.day.seconds, now + 1.day.seconds).first
    assert_equal 1100.2, T.must(activity).bandwidth_up, activity.inspect
    assert_equal 2200.4, T.must(activity).bandwidth_down, activity.inspect
  end

  test "tracks bandwidth and byte hours per owner, actor, and repo" do
    now = Time.now
    owner = create(:user)
    actor = create(:user)
    repo1 = create(:repository)
    repo2 = create(:repository)
    Asset::ActorActivity.track(:lfs, owner.id, actor.id, 0, repo1.id, now,
      up: 1.1, down: 2.2)
    Asset::ActorActivity.track(:lfs, owner.id, actor.id, 0, repo1.id, now,
      up: 10.1, down: 20.2)
    Asset::ActorActivity.track(:lfs, owner.id, actor.id, 0, repo2.id, now,
      up: 100.1, down: 200.2)

    assert activity = Asset::ActorActivity.where(owner_id: owner.id, actor_id: actor.id, repository_id: repo1.id, activity_started_at: now).first
    assert_equal repo1.id, T.must(activity).repository_id, activity.inspect
    assert_equal 11.2, T.must(activity).bandwidth_up, activity.inspect
    assert_equal 22.4, T.must(activity).bandwidth_down, activity.inspect
  end

  test "rejects zero repository_id" do
    now = Time.now
    owner = create(:user)
    actor = create(:user)
    Asset::ActorActivity.track(:lfs, owner.id, actor.id, 0, 0, now,
      up: 1.1, down: 2.2)
    Asset::ActorActivity.track(:lfs, owner.id, actor.id, 0, 0, now,
      up: 10.1, down: 20.2)

    assert Asset::ActorActivity.where(owner_id: owner.id, actor_id: actor.id, activity_started_at: now).count, 0
  end

end
