# typed: true
# frozen_string_literal: true

require "test_helper"

class UserLists::ListCollectionTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "user1")

    @a_list = create(:user_list, name: "A List", user: @user)
    @b_list = create(:user_list, name: "B List", user: @user)

    @repo1 = create(:repository, name: "Cats Are Cool")
    @repo2 = create(:repository, name: "Dogs Are Neat")

    create(:user_list_item, user_list: @a_list, repository: @repo1)
    create(:user_list_item, user_list: @b_list, repository: @repo2)
  end

  test "applies strategy and quacks like an Array" do
    lists = @user.lists

    default_sort = UserLists::ListCollection.new(lists, owner: @user).map(&:name)

    strategy = UserLists::SortingStrategy.new("name", "desc")
    reverse_sort = UserLists::ListCollection.new(lists, sorting_strategy: strategy, owner: @user).map(&:name)

    assert_equal ["A List", "B List"], default_sort
    assert_equal ["B List", "A List"], reverse_sort
  end

  test "has an owner" do
    list = UserLists::ListCollection.new(@user.lists, owner: @user)

    assert_same @user, list.owner
  end
end
