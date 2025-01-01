# typed: true
# frozen_string_literal: true

require "test_helper"

class UserListsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository)

    @user_list = create(:user_list, user: @user)
    @user_list_item = create(:user_list_item, user_list: @user_list, repository: @repo)
  end

  test "deletes lists when a user is deleted" do
    assert_equal 1, UserList.count

    @user.destroy!

    assert_empty UserList.all
  end

  test "correctly establishes inverse relationship with lists" do
    list = @user.lists.take!
    assert_no_queries do
      assert_same list.user, @user
    end
  end

  context "#has_list_with_item?" do
    test "returns whether any of the users lists have an item" do
      other_repo = create(:repository)

      assert @user.has_list_with_item?(@repo)
      refute @user.has_list_with_item?(other_repo)
    end
  end

  context "#count_lists_with_item" do
    test "returns the number of lists with an item" do
      assert_equal 1, @user.count_lists_with_item(@repo)

      create_list(:user_list, 3, user: @user) do |other_list|
        create(:user_list_item, user_list: other_list, repository: @repo)
      end
      create(:user_list, user: @user)

      assert_equal 4, @user.count_lists_with_item(@repo)
    end

    test "returns 0 if no lists have an item" do
      other_repo = create(:repository)

      assert_equal 0, @user.count_lists_with_item(other_repo)
    end
  end

  context "#can_modify_list?" do
    test "is true if the list user is the subject user" do
      assert @user.can_modify_list?(@user_list)
      assert_equal @user.id, @user_list.user_id
    end
  end

  context "#can_create_lists?" do
    test "is true if the user has less than the max number allowed per user" do
      assert_operator @user.lists.count, :<, UserList::MAX_PER_USER
      assert_predicate @user, :can_create_lists?
    end

    test "is false if the user has the maximum number of lists allowed" do
      UserList.stub_const(:MAX_PER_USER, @user.lists.count) do
        refute_predicate @user, :can_create_lists?
      end
    end
  end

  context "#has_created_lists?" do
    test "is true if the user has created a list before" do
      assert_predicate @user, :has_created_lists?
    end

    test "is true if the user has created a list before and has no current lists" do
      @user.lists.destroy_all
      assert_empty @user.lists
      assert_predicate @user, :has_created_lists?
    end

    test "is false if the user has not created any lists" do
      rando = create(:user)
      refute_predicate rando, :has_created_lists?
    end
  end
end
