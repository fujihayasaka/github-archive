# typed: true
# frozen_string_literal: true

require "test_helper"

class AssetActivityTest < GitHub::TestCase

  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)
    @repo2 = create(:repository, owner: @owner)
  end

  test "tracks bandwidth and byte hours per owner" do
    now = Time.now
    Asset::Activity.track(:lfs, @owner.id, @repo.id, now,
      up: 1.1, down: 2.2, source_files: %w(a b c))
    Asset::Activity.track(:lfs, @owner.id, @repo.id, now,
      up: 10.1, down: 20.2, source_files: %w(d e f))

    assert activity = Asset::Activity.where(owner_id: @owner.id, activity_started_at: now).first
    assert_equal 11.2, T.must(activity).bandwidth_up, activity.inspect
    assert_equal 22.4, T.must(activity).bandwidth_down, activity.inspect
    assert_same_elements %w(a b c d e f), T.must(T.must(activity).source_files).split(","), activity.inspect
  end

  test "tracks bandwidth and byte hours per owner and repo" do
    now = Time.now
    Asset::Activity.track(:lfs, @owner.id, @repo.id, now,
      up: 1.1, down: 2.2, source_files: %w(a b c))
    Asset::Activity.track(:lfs, @owner.id, @repo.id, now,
      up: 10.1, down: 20.2, source_files: %w(d e f))
    Asset::Activity.track(:lfs, @owner.id, @repo2.id, now,
      up: 100.1, down: 200.2, source_files: %w(g h i))

    assert activity = Asset::Activity.where(owner_id: @owner.id, repository_id: @repo.id, activity_started_at: now).first
    assert_equal @repo.id, T.must(activity).repository_id, activity.inspect
    assert_equal 11.2, T.must(activity).bandwidth_up, activity.inspect
    assert_equal 22.4, T.must(activity).bandwidth_down, activity.inspect
    assert_same_elements %w(a b c d e f), T.must(T.must(activity).source_files).split(","), activity.inspect
  end

  test "rejects zero repository_id" do
    now = Time.now
    Asset::Activity.track(:lfs, @owner.id, 0, now,
      up: 1.1, down: 2.2, source_files: %w(a b c))
    Asset::Activity.track(:lfs, @owner.id, 0, now,
      up: 10.1, down: 20.2, source_files: %w(d e f))

    assert Asset::Activity.where(owner_id: @owner.id, activity_started_at: now).count, 0
  end

  test "encodes source lines" do
    assert_equal "a", Asset::Activity.encode_source_lines("a", 5)
    assert_equal "a,b,c", Asset::Activity.encode_source_lines(%w(a b c), 5)
    assert_equal "c,d,e", Asset::Activity.encode_source_lines(%w(a b c d e), 5)
    assert_equal "", Asset::Activity.encode_source_lines(",,", 5)
    assert_equal "a", Asset::Activity.encode_source_lines(",,a,", 5)
  end

  test "can add a source file to its list" do
    started_at = Time.now
    Asset::Activity.track(:lfs, @owner.id, @repo.id, started_at, up: 1, source_files: %w(abc123 abc123))
    activity = Asset::Activity.last
    assert_equal T.must(activity).source_files, "abc123"

    Asset::Activity.track(:lfs, @owner.id, @repo.id, started_at, up: 1, source_files: "def456")
    assert_equal "abc123,def456", T.must(activity).reload.source_files
  end

  test "protects against too many source files" do
    source_files = []
    1984.times do
      source_files << SecureRandom.hex
    end

    started_at = Time.now
    Asset::Activity.track(:lfs, @owner.id, @repo.id, started_at, up: 1, source_files: source_files)
    activity = Asset::Activity.last

    last = SecureRandom.hex
    Asset::Activity.track(:lfs, @owner.id, @repo.id, started_at, up: 1, source_files: last)
    assert_equal 65504, T.must(activity).reload.source_files.bytesize
    assert Asset::Activity.seen_source_files(:lfs, @owner.id, @repo.id, started_at).include?(last)

    extra = SecureRandom.hex
    Asset::Activity.track(:lfs, @owner.id, @repo.id, started_at, up: 1, source_files: extra)
    seen = Asset::Activity.seen_source_files(:lfs, @owner.id, @repo.id, started_at)
    assert seen.include?(extra)
    refute seen.include?(source_files.first)

    additional = SecureRandom.hex
    Asset::Activity.track(:lfs, @owner.id, @repo2.id, started_at, up: 1, source_files: additional)
    seen = Asset::Activity.seen_source_files(:lfs, @owner.id, @repo.id, started_at)
    assert seen.include?(extra)
    assert seen.include?(source_files.second)
    refute seen.include?(additional)
  end

  test "knows if it already contains a source file" do
    started_at = Time.now
    Asset::Activity.track(:lfs, @owner.id, @repo.id, started_at, up: 1, source_files: "abc123")
    seen = Asset::Activity.seen_source_files(:lfs, @owner.id, @repo.id, started_at)
    assert seen.include?("abc123")
    refute seen.include?("123abc")
  end

  test "skips track calls without any files" do
    assert_equal 0, Asset::Activity.count
    assert_nil Asset::Activity.track(:lfs, @owner.id, @repo.id, Time.now, up: 1, source_files: [nil, ""])
    assert_equal 0, Asset::Activity.count
  end

  test "fetch for owner by network" do
    started_at = Time.now
    before = 1.hour.ago

    owner = create :user
    other = create :user

    repo1 = create :repository, owner: owner
    repo2 = create(:fork_repository, forker: other, fork_repo: repo1)
    repo3 = create :repository, owner: owner

    Asset::Activity.track(:lfs, owner.id, repo1.id, started_at, up: 1.1, down: 10.1, source_files: ["abc123"])
    Asset::Activity.track(:lfs, owner.id, repo2.id, before, up: 2.2, down: 20.2, source_files: ["abc123"])
    Asset::Activity.track(:lfs, owner.id, repo2.id, started_at, up: 4.4, down: 40.4, source_files: ["abc123"])
    Asset::Activity.track(:lfs, owner.id, repo3.id, started_at, up: 3.3, down: 30.3, source_files: ["abc123"])

    data = Asset::Activity.fetch_for_owner_by_network(:lfs, owner.id, 1.day.ago, 1.day.from_now)

    assert_equal data[repo1.network.id][:bandwidth_up].round(1), 7.7
    assert_equal data[repo1.network.id][:bandwidth_down].round(1), 70.7
    assert_equal data[repo3.network.id][:bandwidth_up].round(1), 3.3
    assert_equal data[repo3.network.id][:bandwidth_down].round(1), 30.3
  end
end
