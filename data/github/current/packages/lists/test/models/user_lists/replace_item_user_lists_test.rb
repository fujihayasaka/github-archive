# typed: true
# frozen_string_literal: true

require "test_helper"

class UserListsReplaceItemUserListsTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository)
    @list0, @list1, @list2 = create_list(:user_list, 3, user: @user)
  end

  test "fails if the user cannot star the repository" do
    @repo.owner.block(@user)
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_ids: [@list0.id],
      context: "tests",
    )

    refute_predicate result, :success?
    refute_predicate result, :did_star?
    refute_predicate result, :did_create?

    refute @repo.starred_by?(@user)
  end

  test "succeeds if nothing is to be done" do
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_ids: [],
      context: "tests",
    )

    assert_predicate result, :success?
    refute_predicate result, :did_star?
    refute_predicate result, :did_create?

    refute @repo.starred_by?(@user)

    refute_hydro_messages(schema: "github.user_lists.v1.UserListAddItem")
    refute_hydro_messages(schema: "github.user_lists.v1.UserListRemoveItem")
  end

  test "adds repository to identified lists and stars the repo" do
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_ids: [@list0.id, @list2.id],
      context: "tests",
    )

    assert_predicate result, :success?
    assert_predicate result, :did_star?
    refute_predicate result, :did_create?

    assert_equal [@repo], @list0.reload.repositories
    assert_empty @list1.reload.items
    assert_equal [@repo], @list2.reload.repositories

    assert @repo.starred_by?(@user)
  end

  test "adds already-starred repository to identified lists" do
    @user.star(@repo)
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_ids: [@list1.id, @list2.id],
      context: "tests",
    )

    assert_predicate result, :success?
    refute_predicate result, :did_star?
    refute_predicate result, :did_create?

    assert_empty @list0.reload.items
    assert_equal [@repo], @list1.reload.repositories
    assert_equal [@repo], @list2.reload.repositories
  end

  test "removes repository from lists not identified" do
    @list0.items.create!(repository: @repo)
    @list2.items.create!(repository: @repo)

    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_ids: [@list0.id, @list1.id],
      context: "tests",
    )

    assert_predicate result, :success?
    assert_predicate result, :did_star?
    refute_predicate result, :did_create?

    assert_equal [@repo], @list0.reload.repositories
    assert_equal [@repo], @list1.reload.repositories
    assert_empty @list2.reload.items

    assert @repo.starred_by?(@user)
  end

  test "removes repository from all lists" do
    @list0.items.create!(repository: @repo)
    @list1.items.create!(repository: @repo)

    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_ids: [],
      context: "tests",
    )

    assert_predicate result, :success?
    refute_predicate result, :did_star?
    refute_predicate result, :did_create?

    assert_empty @list0.reload.items
    assert_empty @list1.reload.items
    assert_empty @list2.reload.items
  end

  test "ignores empty string in list IDs" do
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_ids: [@list0.id, ""],
      context: "tests",
    )

    assert_predicate result, :success?
    assert_predicate result, :did_star?
    refute_predicate result, :did_create?

    assert_equal [@repo], @list0.reload.repositories
    assert_empty @list1.reload.items
    assert_empty @list2.reload.items
  end

  test "ignores list that does not exist" do
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_ids: [-1, @list2.id],
      context: "tests",
    )

    assert_predicate result, :success?
    assert_predicate result, :did_star?
    refute_predicate result, :did_create?

    assert_empty @list0.reload.items
    assert_empty @list1.reload.items
    assert_equal [@repo], @list2.reload.repositories
  end

  test "ignores list that does not belong to user" do
    other_list = create(:user_list)
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_ids: [@list1.id, other_list.id],
      context: "tests",
    )

    assert_predicate result, :success?
    assert_predicate result, :did_star?
    refute_predicate result, :did_create?

    assert_empty @list0.reload.items
    assert_equal [@repo], @list1.reload.repositories
    assert_empty @list2.reload.items
  end

  test "creates lists based on suggested names" do
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_names: ["Suggestion 1", "Suggestion 2"],
      context: "tests",
    )

    assert_predicate result, :success?
    assert_predicate result, :did_star?
    assert_predicate result, :did_create?

    list_one = @user.lists.find_by!(name: "Suggestion 1")
    assert_equal [@repo], list_one.repositories
    list_two = @user.lists.find_by!(name: "Suggestion 2")
    assert_equal [@repo], list_two.repositories
  end

  test "finds an existing list with a name that conflicts with a suggestion" do
    existing_list = create(:user_list, user: @user, name: "Existing Suggestion?")

    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_names: ["existinG suggestioN!"],
      context: "tests",
    )

    assert_predicate result, :success?
    refute_predicate result, :did_create?

    assert_equal [@repo], existing_list.reload.repositories
  end

  test "ignores blank names" do
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_names: ["One", "", "two!"],
      context: "tests",
    )

    assert_predicate result, :success?
    assert_predicate result, :did_star?
    assert_predicate result, :did_create?

    assert_equal [@repo], @user.lists.find_by!(name: "One").repositories
    assert_equal [@repo], @user.lists.find_by!(name: "two!").repositories
  end

  test "fails if the user cannot star the repository but reports if suggested list was still created" do
    @repo.owner.block(@user)
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_names: ["Created regardless"],
      context: "tests",
    )

    refute_predicate result, :success?
    refute_predicate result, :did_star?
    assert_predicate result, :did_create?

    refute @repo.starred_by?(@user)

    list = @user.lists.find_by!(name: "Created regardless")
    assert_empty list.repositories
  end

  test "accepts both list names and IDs at once" do
    result = UserLists::ReplaceItemUserLists.call(
      user: @user,
      item: @repo,
      requested_list_names: ["aaa", "", "bbb"],
      requested_list_ids: [@list0.id, @list1.id, @list2.id],
      context: "tests",
    )

    assert_predicate result, :success?
    assert_predicate result, :did_star?
    assert_predicate result, :did_create?

    assert_equal [@repo], @user.lists.find_by!(name: "aaa").repositories
    assert_equal [@repo], @user.lists.find_by!(name: "bbb").repositories
    assert_equal [@repo], @list0.reload.repositories
    assert_equal [@repo], @list1.reload.repositories
    assert_equal [@repo], @list2.reload.repositories
  end

  test "emits Hydro event when adding an item to a list" do
    assert_difference(-> { @repo.reload.stargazer_count }) do
      UserLists::ReplaceItemUserLists.call(
        user: @user,
        item: @repo,
        requested_list_ids: [@list0.id],
        context: "tests",
      )
    end

    new_list_item = @list0.items.last
    refute_nil new_list_item

    message = {
      user_list_item: {
        id: new_list_item.id,
        user_list_id: @list0.id,
        repository_id: @repo.id,
        created_at: new_list_item.created_at,
      },
      repository: Hydro::EntitySerializer.repository(@repo),
      repository_owner: Hydro::EntitySerializer.user(@repo.owner),
      user: Hydro::EntitySerializer.user(@user),
      user_list: Hydro::EntitySerializer.user_list(@list0),
    }

    assert_hydro_published(message, schema: "github.user_lists.v1.UserListAddItem")
    assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListAddItem")
  end

  test "emits Hydro event when removing an item from a list" do
    list_item = create(:user_list_item, user_list: @list0, repository: @repo)

    assert_difference(-> { UserListItem.count }, -1) do
      UserLists::ReplaceItemUserLists.call(
        user: @user,
        item: @repo,
        requested_list_ids: [],
        context: "tests",
      )
    end

    message = {
      user_list_item: {
        id: list_item.id,
        user_list_id: @list0.id,
        repository_id: @repo.id,
        created_at: list_item.created_at,
      },
      repository: Hydro::EntitySerializer.repository(@repo),
      repository_owner: Hydro::EntitySerializer.user(@repo.owner),
      user: Hydro::EntitySerializer.user(@user),
      user_list: Hydro::EntitySerializer.user_list(@list0),
    }

    assert_hydro_published(message, schema: "github.user_lists.v1.UserListRemoveItem")
    assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListRemoveItem")
  end
end
