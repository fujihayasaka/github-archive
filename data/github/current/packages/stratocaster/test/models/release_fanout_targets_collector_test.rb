# typed: true
# frozen_string_literal: true

require "test_helper"

class ReleaseFanoutTargetsCollectorTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  setup do
    @repo = create(:repository, :full_creation)
    @user = @repo.owner

    commit = @repo.commits.create({ committer: @user, message: "this is commit", author: @user }, nil) do |files|
      files.add("a-file", "a-content")
    end
    @repo.refs.create("refs/heads/main", commit, @repo.owner)

    @release = create(:release,
      name: "Version One!",
      tag_name: "v1",
      author: @user,
      repository: @repo,
      target_commitish: "main",
      body: "nice release, @#{@user}"
    )
  end

  def collector(release = nil)
    Release::FanoutTargetsCollector.new(release || @release)
  end

  test "includes followers of the release author" do
    followers = 3.times.map do
      follower = create(:verified_user)
      follower.follow @release.author
      follower
    end

    targets = collector.targets
    followers.each { |f| assert_includes targets, f.id }

    assert_dogstats_count_value(3, "#{Release::FanoutTargetsCollector::STATS_PREFIX}.release_author_followers")
    assert_dogstats_distribution(1, "release.fanout.release_author_followers.time")
  end

  test "excludes spammy followers of the release author", skip_enterprise: true do
    followers = 3.times.map do
      follower = create(:verified_user)
      follower.follow @release.author
      follower
    end

    spammy_follower = create(:spammy_user)
    spammy_follower.follow @release.author

    targets = collector.targets
    followers.each { |f| assert_includes targets, f.id }
    refute_includes targets, spammy_follower.id

    assert_dogstats_count_value(3, "#{Release::FanoutTargetsCollector::STATS_PREFIX}.release_author_followers")
    assert_dogstats_distribution(1, "release.fanout.release_author_followers.time")
  end

  test "excludes suspended followers of the release author" do
    followers = 3.times.map do
      follower = create(:verified_user)
      follower.follow @release.author
      follower
    end

    spammy_follower = create(:suspended_user)
    spammy_follower.follow @release.author

    targets = collector.targets
    followers.each { |f| assert_includes targets, f.id }
    refute_includes targets, spammy_follower.id

    assert_dogstats_count_value(3, "#{Release::FanoutTargetsCollector::STATS_PREFIX}.release_author_followers")
    assert_dogstats_distribution(1, "release.fanout.release_author_followers.time")
  end

  test "does not includes stargazers" do
    stargazers = 4.times.map do
      stargazer = create(:user)
      stargazer.star @repo
      stargazer
    end

    targets = collector.targets
    stargazers.each { |s| refute_includes targets, s.id }

    assert_dogstats_count(0, "#{Release::FanoutTargetsCollector::STATS_PREFIX}.stargazers")
    assert_dogstats_distribution(0, "release.fanout.stargazers.time")
  end

  test "instruments hydro event" do
    _ = collector.targets

    message = {
      release: Hydro::EntitySerializer.release(@release),
      repository: Hydro::EntitySerializer.repository(@repo),
      author: Hydro::EntitySerializer.user(@user),
      total_targets: 0,
      total_commit_author_followers: 0,
      total_release_author_followers: 0,
      total_stargazers: 0,
    }
    assert_hydro_published_partial(message, schema: "github.releases.v1.FanoutTargetsCollected")
  end
end
