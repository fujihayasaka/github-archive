# typed: true
# frozen_string_literal: true

require "test_helper"

class UserPopularRepositoriesTest < GitHub::TestCase
  fixtures do
    @user = create(:user, plan: "medium")
    @priv_repo = create(:private_repository, owner: @user, name: "priv_repo")
    @repo1 = create(:repository, owner: @user, name: "repo1")
    @repo2 = create(:repository, owner: @user, name: "repo2")
    @repo3 = create(:repository, owner: @user, name: "repo3")
    @repo4 = create(:repository, owner: @user, name: "repo4")
    @repo5 = create(:repository, owner: @user, name: "repo5")
    @repo6 = create(:repository, owner: @user, name: "repo6")

    @user2 = create(:user)
    @user3 = create(:user)
    @user4 = create(:user)

    # make repo2 the most popular repo, followed by repo1
    @user2.star @repo2
    @user3.star @repo2
    @user4.star @repo2
    @user2.star @repo1
  end

  setup do
    @fetcher = User::PopularRepositories.new(@user)
  end

  context "#repositories" do
    test "returns an empty list for user with no repositories" do
      user = create(:user)
      fetcher = User::PopularRepositories.new(user)
      assert_equal [], fetcher.repositories
    end

    test "returns repos sorted by popularity (i.e. most stars)" do
      result = @fetcher.repositories
      assert_equal @repo2, result[0], "Most starred repo should be first"
      assert_equal @repo1, result[1], "Second most starred repo should be second"
      assert_same_elements [@repo3, @repo4, @repo5, @repo6], result.offset(2)
    end

    test "does not return private repos" do
      @user2.star @priv_repo
      refute_includes @fetcher.repositories, @priv_repo
    end

    test "returns number of repos based on limit" do
      viewer = create(:user)
      fetcher = User::PopularRepositories.new(@user)

      assert_equal fetcher.limit, fetcher.repositories.size
    end
  end
end
