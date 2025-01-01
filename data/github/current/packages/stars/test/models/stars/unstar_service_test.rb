# typed: true
# frozen_string_literal: true

require "test_helper"

class StarsUnstarServiceTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository)
  end

  test "unstars a starred repository without confirmation when the repository is not on any lists" do
    @user.star(@repo)

    result = Stars::UnstarService.call(
      repository: @repo,
      actor: @user,
      context: "other",
      confirm: false,
    )

    assert_predicate result, :success?

    refute @repo.starred_by?(@user)
    assert_equal 0, @repo.reload.stargazer_count

    assert_dogstats_increment(1, "star", tags: ["action:unstar"])
  end

  test "unstars an unstarred repository without confirmation when the repository is not on any lists" do
    result = Stars::UnstarService.call(
      repository: @repo,
      actor: @user,
      context: "other",
      confirm: false,
    )

    assert_predicate result, :success?

    refute @repo.starred_by?(@user)
    assert_equal 0, @repo.stargazer_count

    assert_dogstats_increment(0, "star", tags: ["action:unstar"])
  end

  test "fails to unstar without confirmation when the repository is on a list" do
    @user.star(@repo)
    list = create(:user_list, user: @user)
    create(:user_list_item, user_list: list, repository: @repo)

    result = Stars::UnstarService.call(
      repository: @repo,
      actor: @user,
      context: "other",
      confirm: false,
    )

    assert_predicate result, :unconfirmed?

    assert @repo.starred_by?(@user)
    assert_equal 1, @repo.stargazer_count
    assert_equal [@repo], list.reload.repositories

    assert_dogstats_increment(0, "star", tags: ["action:unstar"])
  end

  test "includes the list count when failing to unstar a repository on many lists" do
    @user.star(@repo)
    create_list(:user_list, 3, user: @user) do |list|
      create(:user_list_item, user_list: list, repository: @repo)
    end

    result = Stars::UnstarService.call(
      repository: @repo,
      actor: @user,
      context: "other",
      confirm: false,
    )

    assert_predicate result, :unconfirmed?
    assert_equal 3, result.list_count

    assert @repo.starred_by?(@user)
    assert_equal 1, @repo.stargazer_count
    @user.lists.each do |list|
      assert_equal [@repo], list.reload.repositories
    end

    assert_dogstats_increment(0, "star", tags: ["action:unstar"])
  end

  test "unstars a repository with confirmation when the repository is on a list" do
    @user.star(@repo)
    list = create(:user_list, user: @user)
    create(:user_list_item, user_list: list, repository: @repo)

    result = Stars::UnstarService.call(
      repository: @repo,
      actor: @user,
      context: "other",
      confirm: true,
    )

    assert_predicate result, :success?

    refute @repo.starred_by?(@user)
    assert_equal 0, @repo.reload.stargazer_count
    assert_empty list.reload.repositories

    assert_dogstats_increment(1, "star", tags: ["action:unstar"])
  end
end
