# typed: true
# frozen_string_literal: true

require "test_helper"

class LatestReleaseDependencyTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create :repository, from_example: :repository_test_simple
    setup_search
  end

  test "#set_latest_release" do
    release = create :release, repository: @repo
    release2 = create :release, repository: @repo
    draft = create :release, repository: @repo, draft: true

    # creates
    assert @repo.set_latest_release(release)
    assert_equal release, @repo.reload.saved_latest_release
    assert_equal 1, RepositoryLatestRelease.where(repository_id: @repo.id).count

    # updates
    assert @repo.set_latest_release(release2)
    assert_equal release2, @repo.reload.saved_latest_release
    assert_equal 1, RepositoryLatestRelease.where(repository_id: @repo.id).count

    # cannot set draft release as latest
    refute @repo.set_latest_release(draft)
  end

  context "#latest_release" do
    test "correctly handles two releases with the same target" do
      first_release = Timecop.travel(5.minutes.ago) do
        create :release, name: "Version One!", tag_name: "v1.0", author: @repo.owner, repository: @repo
      end
      second_release = create :release, name: "Version Oneish!", tag_name: "v1.0.ish", author: @repo.owner, repository: @repo

      # the created_at references the target
      assert_equal second_release.created_at, first_release.created_at
      refute_equal second_release.updated_at, first_release.updated_at

      latest_release = nil
      make_searchable *@repo.releases
      latest_release = @repo.latest_release(@repo.owner)

      assert_equal second_release, latest_release
    end

    test "uses stored latest release" do
      release = create :release, repository: @repo
      @repo.set_latest_release(release)

      # make sure we aren't taking the fallback
      Release.expects(:query_releases).never

      assert_equal release, @repo.latest_release(@repo.owner)
    end

    test "fallback to querying Elasticsearch if stored latest is invalid" do
      release = create :release, repository: @repo
      release2 = create :release, repository: @repo

      @repo.set_latest_release(release)

      # Make the stored latest an invalid Latest release by skipping the after commit callback when updating it
      # This should never happen, this test is here to make sure our *extra* safety net works
      Release.skip_callback(:commit, :after, :clear_latest_if_no_longer_valid)
      release.update(prerelease: true)

      # The db stored latest release should remain the same
      assert_equal release, T.must(RepositoryLatestRelease.find_by(repository_id: @repo.id)).release

      # Release methods should correctly handle the invalid stored latest
      make_searchable *@repo.releases

      assert_equal false, release.is_latest?(@repo.owner)
      assert_equal release2, @repo.latest_release(@repo.owner)
      assert_dogstats_increment 1, "latest_release.fallback", tags: ["reason:latest_release_invalid"]
    end

    test "logs telemetry when falling back to Elasticsearch" do
      release = create :release, repository: @repo
      make_searchable *@repo.releases
      assert @repo.latest_release(@repo.owner)
      assert_dogstats_increment 1, "latest_release.fallback", tags: ["reason:latest_release_nil"]
    end
  end

  test "destroys dependent repository_latest_release" do
    release = create :release, repository: @repo
    @repo.set_latest_release(release)

    @repo.reload.destroy!

    assert_equal 0, RepositoryLatestRelease.where(repository_id: @repo.id).count
  end
end
