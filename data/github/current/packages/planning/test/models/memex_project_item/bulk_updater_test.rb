# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItem::BulkUpdaterTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user, :verified)
    @repo = create(:repository, owner: @user)
    @memex = create(:memex_project, owner: @user)
    @item1, @item2 = create_pair(:memex_project_item, memex_project: @memex)
  end

  context ".perform" do
    test "returns result with success=true when all items updated successfully" do
      data = { bulkUpdateSuccess: true, actor: { id: @user.id }, bulkUpdateErrors: [] }
      @memex.expects(:notify_memex_channel).once.with(data)

      result = MemexProjectItem::BulkUpdater.perform(
        item_ids: [@item1.id, @item2.id],
        memex_project: @memex,
        user: @user,
        item_params: [
          {
            id: @item1.id,
            memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: "Some new title" } }],
          },
          {
            id: @item2.id,
            memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: "Other title" } }],
          },
        ],
      )

      assert_instance_of MemexProjectItem::BulkUpdater::Result, result
      assert_predicate result, :success?
      assert_same_elements [@item1, @item2], result.items
      assert_empty result.errors
      assert_equal 2, result.total_updated_items
      assert_equal 0, result.total_failed_items
      assert_equal "Some new title", @item1.content.reload.title
      assert_equal "Other title", @item2.content.reload.title
      assert_dogstats_timing(1, "memex.update_bulk")
    end

    test "returns result with success=false when no updates complete" do
      original_title = @item1.content.title
      fake_errors = stub(full_messages: ["o noes", "dear me"])
      MemexProjectItem.any_instance.stubs(:errors).returns(fake_errors)

      MemexProjectItem.any_instance.expects(:set_column_value).once.returns(false)

      expected_errors = [{ memexProjectItemId: @item1.id, message: "o noes and dear me" }]
      data = { bulkUpdateSuccess: false, actor: { id: @user.id }, bulkUpdateErrors: expected_errors }
      @memex.expects(:notify_memex_channel).once.with(data)

      result = MemexProjectItem::BulkUpdater.perform(
        item_ids: [@item1.id],
        memex_project: @memex,
        user: @user,
        item_params: [{
          id: @item1.id,
          memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: "oops no" } }],
        }],
      )

      assert_instance_of MemexProjectItem::BulkUpdater::Result, result
      refute_predicate result, :success?
      assert_equal [@item1], result.items
      assert_equal 1, result.errors.size
      bulk_update_error = T.must(result.errors.first)
      assert_equal "o noes and dear me", bulk_update_error.message
      assert_equal @item1.id, bulk_update_error.memex_project_item_id
      assert_equal 1, result.total_failed_items
      assert_equal original_title, @item1.content.reload.title
      assert_dogstats_timing(1, "memex.update_bulk")
    end

    test "returns result with success=false when only some updates complete" do
      original_title = @item1.content.title
      expected_errors = [{ memexProjectItemId: @item1.id, message: "Title is too long (maximum is 256 characters)" }]
      data = { bulkUpdateSuccess: false, actor: { id: @user.id }, bulkUpdateErrors: expected_errors }
      @memex.expects(:notify_memex_channel).once.with(data)
      invalid_title = "a" * (Issue::TITLE_BYTESIZE_LIMIT + 1)

      result = MemexProjectItem::BulkUpdater.perform(
        item_ids: [@item1.id, @item2],
        memex_project: @memex,
        user: @user,
        item_params: [
          {
            id: @item1.id,
            memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: invalid_title } }],
          },
          {
            id: @item2.id,
            memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: "Some new title" } }],
          },
        ],
      )

      assert_instance_of MemexProjectItem::BulkUpdater::Result, result
      refute_predicate result, :success?
      assert_equal [@item1, @item2], result.items
      assert_equal 1, result.errors.size
      bulk_update_error = T.must(result.errors.first)
      assert_equal "Title is too long (maximum is 256 characters)", bulk_update_error.message
      assert_equal @item1.id, bulk_update_error.memex_project_item_id
      assert_equal 1, result.total_updated_items
      assert_equal 1, result.total_failed_items
      assert_equal original_title, @item1.content.reload.title
      assert_equal "Some new title", @item2.content.reload.title
      assert_dogstats_timing(1, "memex.update_bulk")
    end

    test "does not send websocket notification when notify_channel=false" do
      @memex.expects(:notify_memex_channel).never

      result = MemexProjectItem::BulkUpdater.perform(
        item_ids: [@item1.id],
        memex_project: @memex,
        user: @user,
        item_params: [
          {
            id: @item1.id,
            memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: "Some new title" } }],
          },
        ],
        notify_channel: false,
      )

      assert_instance_of MemexProjectItem::BulkUpdater::Result, result
      assert_predicate result, :success?
      assert_same_elements [@item1], result.items
      assert_empty result.errors
      assert_equal 1, result.total_updated_items
      assert_equal 0, result.total_failed_items
      assert_equal "Some new title", @item1.content.reload.title
      assert_dogstats_timing(1, "memex.update_bulk")
    end
  end
end
