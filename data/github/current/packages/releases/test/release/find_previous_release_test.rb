# typed: true
# frozen_string_literal: true

require "test_helper"

class Release::FindPreviousReleaseTest < GitHub::TestCase
  include HydroTestHelpers

  test "only searches tags up to MAX_TAGS" do
    repo = create(:repository, from_example: :tags_galore)

    # v1.0

    first_release = create(:release,
      name: "v1.0",
      tag_name: "v1.0",
      author: repo.owner,
      repository: repo,
      target_commitish: "master"
    )

    # v2.0

    second_release = create(:release,
      name: "v2.0",
      tag_name: "v2.0",
      author: repo.owner,
      repository: repo,
      target_commitish: "master"
    )

    # v3.0
    # v3.0.1
    # v3.0.2
    # v3.0.3

    # v4.0
    final_release = create(:release,
      name: "v4.0",
      tag_name: "v4.0",
      author: repo.owner,
      repository: repo,
      target_commitish: "master"
    )

    Release::FindPreviousRelease.stub_const(:BATCH_SIZE, 1) do
      Release::FindPreviousRelease.stub_const(:MAX_TAGS, 2) do
        assert_equal first_release, second_release.previous_release
        assert_nil final_release.previous_release
      end
    end
  end

  test "finds a release up to MAX_TAGS" do
    repo = create(:repository, from_example: :tags_galore)

    # v1.0

    first_release = create(:release,
      name: "v1.0",
      tag_name: "v1.0",
      author: repo.owner,
      repository: repo,
      target_commitish: "master"
    )

    # v2.0
    # v3.0
    # v3.0.1
    # v3.0.2
    # v3.0.3

    # v4.0
    second_release = create(:release,
      name: "v4.0",
      tag_name: "v4.0",
      author: repo.owner,
      repository: repo,
      target_commitish: "master"
    )

    Release::FindPreviousRelease.stub_const(:BATCH_SIZE, 1) do
      assert_equal first_release, second_release.previous_release
    end
  end

  test "instruments hydro event" do
    repo = create(:repository, from_example: :tags_galore)

    first_release = create(:release,
      name: "v1.0",
      tag_name: "v1.0",
      author: repo.owner,
      repository: repo,
      target_commitish: "master"
    )

    # v2.0

    second_release = create(:release,
      name: "v2.0",
      tag_name: "v2.0",
      author: repo.owner,
      repository: repo,
      target_commitish: "master"
    )

    _ = second_release.commits

    commits_fetched_message = {
      since: :PREVIOUS_RELEASE,
      commits_fetched: 1,
      total_commits: 2,
      repository: Hydro::EntitySerializer.repository(repo),
      release: Hydro::EntitySerializer.release(second_release),
      previous_release: Hydro::EntitySerializer.release(first_release),
    }
    assert_hydro_published(commits_fetched_message, schema: "github.releases.v1.CommitsFetched")

    previous_release_fetched_message = {
      release: Hydro::EntitySerializer.release(second_release),
      previous_release: Hydro::EntitySerializer.release(first_release),
      tags_fetched_limit_reached: false,
      repository: Hydro::EntitySerializer.repository(repo),
    }
    assert_hydro_published_partial(previous_release_fetched_message, schema: "github.releases.v1.PreviousReleaseFetched")
  end

  test "finds previous release for release object with pending tag" do
    repo = create(:repository, from_example: :tags_galore)

    # v1.0

    first_release = create(:release,
      name: "v1.0",
      tag_name: "v1.0",
      author: repo.owner,
      repository: repo,
      target_commitish: "master"
    )

    release_with_pending_tag = build(:release,
      name: "v2.1",
      tag_name: "tag doesn't exist",
      author: repo.owner,
      repository: repo,
      target_commitish: "master"
    )

    assert_equal release_with_pending_tag.previous_release, first_release

  end
end
