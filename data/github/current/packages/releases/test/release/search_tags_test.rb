# typed: true
# frozen_string_literal: true

require "test_helper"

class Release::SearchTagsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    #repo with lots of tags
    @repo = create :repository, owner: @user, from_example: :tags_galore

    # repo with tags v1, v2
    @simple_repo = create :repository, owner: @user, from_example: :simple
  end

  setup do
    example_repo :simple, @simple_repo
    example_repo :tags_galore, @repo
  end

  test "finds previous semver tag with v prefix" do
    rel = create :release, repository: @repo, tag_name: "v3.0.2"
    found_tag = Release::SearchTags.new(rel).find_previous_version_tag

    assert_equal found_tag, "v3.0.1"
  end

  test "find previous semver tag without v prefix, skips invalid semver tags and rc tags" do
    new_commit = create :commit, repository: @repo
    create :release, repository: @repo, tag_name: "4.1.0", target_commitish: new_commit.sha

    # create 2 filler invalid semver tags in between (by creating releases)
    new_commit = create :commit, repository: @repo
    create :release, repository: @repo, tag_name: "vInvalid", target_commitish: new_commit.sha

    new_commit = create :commit, repository: @repo
    create :release, repository: @repo, tag_name: "4.2.1-rc1", target_commitish: new_commit.sha

    # create a new release and tag where we will look back from
    new_commit = create :commit, repository: @repo
    rel = create :release, repository: @repo, tag_name: "4.2.0", target_commitish: new_commit.sha

    found_tag = Release::SearchTags.new(rel).find_previous_version_tag

    assert_equal found_tag, "4.1.0"
  end

  test "returns nil when no prior valid tag" do
    rel = create :release, repository: @repo, tag_name: "v1.0"
    found_tag = Release::SearchTags.new(rel).find_previous_version_tag

    assert_nil found_tag
  end

  test "returns nil after hitting the search limit" do
    # create some tags, we *would* find v3.0.0 but we will hit the limit
    new_commit = create :commit, repository: @simple_repo
    create :release, repository: @simple_repo, tag_name: "v3.0.0", target_commitish: new_commit.sha

    new_commit = create :commit, repository: @simple_repo
    create :release, repository: @simple_repo, tag_name: "vInvalid", target_commitish: new_commit.sha

    found_tag = T.let(nil, T.nilable(String))
    Release::SearchTags.stub_const(:MAX_TAGS_TO_SEARCH, 1) do
      new_commit = create :commit, repository: @simple_repo
      rel = create :release, repository: @simple_repo, tag_name: "v4.1.0", target_commitish: "master"
      found_tag = Release::SearchTags.new(rel).find_previous_version_tag
    end

    assert_nil found_tag
  end

  test "considers multiple tags referencing the same commit" do
    # multiple tags referencing the same commit
    # git-describe by default is going to return v3.0
    # we need to make sure we are going to keep looking and find v3.0.0
    new_commit = create :commit, repository: @simple_repo
    create :release, repository: @simple_repo, tag_name: "v3", target_commitish: new_commit.sha
    create :release, repository: @simple_repo, tag_name: "v3.0.0", target_commitish: new_commit.sha
    create :release, repository: @simple_repo, tag_name: "v3.0", target_commitish: new_commit.sha

    new_commit = create :commit, repository: @simple_repo
    rel = create :release, repository: @simple_repo, tag_name: "v4.0.0", target_commitish: "master"
    found_tag = Release::SearchTags.new(rel).find_previous_version_tag

    assert_equal found_tag, "v3"
  end

  test "finds tag with leading 0s in parts" do
    new_commit = create :commit, repository: @repo
    create :release, repository: @repo, tag_name: "2018.03.01", target_commitish: new_commit.sha

    new_commit = create :commit, repository: @repo
    rel = create :release, repository: @repo, tag_name: "2018.03.02", target_commitish: new_commit.sha

    found_tag = Release::SearchTags.new(rel).find_previous_version_tag

    assert_equal found_tag, "2018.03.01"
  end

  test "does not search for previous version tag if new tag is not valid semver" do
    new_commit = create :commit, repository: @repo
    create :release, repository: @repo, tag_name: "v3.0.0", target_commitish: new_commit.sha

    new_commit = create :commit, repository: @repo
    rel = create :release, repository: @repo, tag_name: "vNew", target_commitish: new_commit.sha

    found_tag = Release::SearchTags.new(rel).find_previous_version_tag

    assert_nil found_tag
  end
end
