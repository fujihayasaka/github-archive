# typed: true
# frozen_string_literal: true

require "test_helper"

class UserListItemTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @potential_sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
    @sponsorable = create(:user, :sponsorable)
    @sponsorable_repo = create(:repository, owner: @sponsorable)
  end

  context ".bulk_insert" do
    test "adds repo to each list" do
      user = create(:user)
      list1, list2 = create_list(:user_list, 2, user: user)

      result = assert_difference(-> { UserListItem.count }, 2) do
        UserListItem.bulk_insert(user_id: user.id, repository_id: @sponsorable_repo.id,
          list_ids: [list1.id, list2.id])
      end

      assert_same_elements [list1.id, list2.id], result, "should have returned IDs of lists that were changed"
      assert_equal [@sponsorable_repo], list1.repositories
      assert_equal [@sponsorable_repo], list2.repositories
    end

    test "emits Hydro event for adding a list item" do
      travel_to(Time.now) do
        user = create(:user)
        list = create(:user_list, user: user)
        message = {
          user_list_item: {
            user_list_id: list.id,
            repository_id: @sponsorable_repo.id,
            created_at: Time.now,
          },
          repository: Hydro::EntitySerializer.repository(@sponsorable_repo),
          repository_owner: Hydro::EntitySerializer.user(@sponsorable),
          user: Hydro::EntitySerializer.user(user),
          user_list: Hydro::EntitySerializer.user_list(list),
        }

        result = assert_difference(-> { UserListItem.count }) do
          UserListItem.bulk_insert(user_id: user.id, repository_id: @sponsorable_repo.id, list_ids: [list.id])
        end

        assert_equal [list.id], result
        new_list_item = list.items.last
        refute_nil new_list_item
        message[:user_list_item][:id] = new_list_item.id
        assert_hydro_published(message, schema: "github.user_lists.v1.UserListAddItem")
        assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListAddItem")
      end
    end

    test "does not emit Hydro event for adding a list item that was already on a list" do
      user = create(:user)
      list = create(:user_list, user: user)
      create(:user_list_item, user_list: list, repository: @sponsorable_repo)
      reset_hydro

      result = assert_no_difference(-> { UserListItem.count }) do
        UserListItem.bulk_insert(user_id: user.id, repository_id: @sponsorable_repo.id, list_ids: [list.id])
      end

      assert_empty result
      refute_hydro_messages(schema: "github.user_lists.v1.UserListAddItem")
    end
  end

  context ".bulk_delete" do
    test "removes repository from each list that's not specified" do
      user = create(:user)
      list_to_keep, list_to_remove = create_list(:user_list, 2, user: user)

      # Put our target repo in both lists:
      list_to_keep_item = create(:user_list_item, user_list: list_to_keep, repository: @sponsorable_repo)
      list_to_remove_item = create(:user_list_item, user_list: list_to_remove, repository: @sponsorable_repo)

      # Add some other items to those lists, to make sure they aren't affected:
      other_list_to_keep_item = create(:user_list_item, user_list: list_to_keep)
      other_list_to_remove_item = create(:user_list_item, user_list: list_to_remove)

      result = assert_difference(-> { UserListItem.count }, -1) do
        UserListItem.bulk_delete(user_id: user.id, repository_id: @sponsorable_repo.id,
          list_ids_to_keep: [list_to_keep.id])
      end

      assert_same_elements [list_to_remove.id], result, "should have returned IDs of lists that were changed"
      assert_same_elements [list_to_keep_item, other_list_to_keep_item], list_to_keep.items
      assert_equal [other_list_to_remove_item], list_to_remove.items
      refute UserListItem.exists?(list_to_remove_item.id)
    end

    test "emits Hydro event for removing a list item" do
      list_item = create(:user_list_item, repository: @sponsorable_repo)
      message = {
        user_list_item: {
          id: list_item.id,
          user_list_id: list_item.user_list_id,
          repository_id: @sponsorable_repo.id,
          created_at: list_item.created_at,
        },
        repository: Hydro::EntitySerializer.repository(@sponsorable_repo),
        repository_owner: Hydro::EntitySerializer.user(@sponsorable),
        user: Hydro::EntitySerializer.user(list_item.list_owner),
        user_list: Hydro::EntitySerializer.user_list(list_item.user_list),
      }

      result = assert_difference(-> { UserListItem.count }, -1) do
        UserListItem.bulk_delete(user_id: list_item.list_owner.id, repository_id: @sponsorable_repo.id, list_ids_to_keep: [])
      end

      assert_equal [message[:user_list][:id]], result
      assert_hydro_published(message, schema: "github.user_lists.v1.UserListRemoveItem")
      assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListRemoveItem")
    end
  end

  context "#instrument_create" do
    test "emits a UserListAddItem Hydro event" do
      list = create(:user_list)
      repo = create(:repository)
      list_item = create(:user_list_item, user_list: list, repository: repo)
      message = {
        user_list_item: {
          id: list_item.id,
          user_list_id: list.id,
          repository_id: repo.id,
          created_at: list_item.created_at,
        },
        repository: Hydro::EntitySerializer.repository(repo),
        repository_owner: Hydro::EntitySerializer.user(repo.owner),
        user: Hydro::EntitySerializer.user(list.user),
        user_list: Hydro::EntitySerializer.user_list(list),
      }
      reset_hydro

      list_item.instrument_create

      assert_hydro_published(message, schema: "github.user_lists.v1.UserListAddItem")
      assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListAddItem")
    end
  end

  context "#instrument_delete" do
    test "emits a UserListRemoveItem Hydro event" do
      list = create(:user_list)
      repo = create(:repository)
      list_item = create(:user_list_item, user_list: list, repository: repo)
      message = {
        user_list_item: {
          id: list_item.id,
          user_list_id: list.id,
          repository_id: repo.id,
          created_at: list_item.created_at,
        },
        repository: Hydro::EntitySerializer.repository(repo),
        repository_owner: Hydro::EntitySerializer.user(repo.owner),
        user: Hydro::EntitySerializer.user(list.user),
        user_list: Hydro::EntitySerializer.user_list(list),
      }

      list_item.instrument_delete

      assert_hydro_published(message, schema: "github.user_lists.v1.UserListRemoveItem")
      assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListRemoveItem")
    end
  end

  context "instrumentation" do
    test "emits a Hydro event on create" do
      travel_to(Time.now) do
        list = create(:user_list)
        repo = create(:repository)
        message = {
          user_list_item: {
            user_list_id: list.id,
            repository_id: repo.id,
            created_at: Time.now,
          },
          repository: Hydro::EntitySerializer.repository(repo),
          repository_owner: Hydro::EntitySerializer.user(repo.owner),
          user: Hydro::EntitySerializer.user(list.user),
          user_list: Hydro::EntitySerializer.user_list(list),
        }

        list_item = create(:user_list_item, user_list: list, repository: repo)

        message[:user_list_item][:id] = list_item.id
        assert_hydro_published(message, schema: "github.user_lists.v1.UserListAddItem")
        assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListAddItem")
      end
    end

    test "emits a Hydro event on delete" do
      list = create(:user_list)
      repo = create(:repository)
      list_item = create(:user_list_item, user_list: list, repository: repo)
      message = {
        user_list_item: {
          id: list_item.id,
          user_list_id: list.id,
          repository_id: repo.id,
          created_at: list_item.created_at,
        },
        repository: Hydro::EntitySerializer.repository(repo),
        repository_owner: Hydro::EntitySerializer.user(repo.owner),
        user: Hydro::EntitySerializer.user(list.user),
        user_list: Hydro::EntitySerializer.user_list(list),
      }

      list_item.destroy!

      assert_hydro_published(message, schema: "github.user_lists.v1.UserListRemoveItem")
      assert_hydro_messages(count: 1, schema: "github.user_lists.v1.UserListRemoveItem")
    end
  end

  context "updates its UserList's item count and last_added_at" do
    test "on create" do
      list = travel_to(1.hour.ago) { create(:user_list) }
      assert_equal 0, list.item_count
      original_last_added_at = list.last_added_at
      refute_nil original_last_added_at

      create(:user_list_item, user_list: list)

      assert_equal 1, list.reload.item_count
      refute_nil list.last_added_at
      refute_equal original_last_added_at, list.last_added_at, "should have updated the last_added_at"
    end

    test "does not emit a UserListUpdate Hydro event" do
      list = create(:user_list)

      list_item = assert_difference(-> { list.reload.item_count }) do
        create(:user_list_item, user_list: list)
      end
      assert_difference(-> { list.reload.item_count }, -1) do
        list_item.destroy!
      end

      refute_hydro_messages(schema: "github.user_lists.v1.UserListUpdate")
    end

    test "on destroy" do
      list = travel_to(1.hour.ago) { create(:user_list) }
      item = create(:user_list_item, user_list: list)
      assert_equal 1, list.item_count
      original_last_added_at = list.last_added_at
      refute_nil original_last_added_at

      item.destroy

      assert_equal 0, list.reload.item_count
      refute_nil list.last_added_at
      refute_equal original_last_added_at, list.last_added_at, "should have updated the last_added_at"
    end
  end
end
