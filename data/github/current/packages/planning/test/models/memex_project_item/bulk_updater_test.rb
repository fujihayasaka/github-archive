# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItem::BulkUpdaterTest < GitHub::TestCase
  include DogstatsTestHelpers
  include MemexHelpers

  fixtures do
    @user = create(:user, :verified)
    @repo = create(:repository, owner: @user)
    @memex = create(:memex_project, owner: @user)
    @item1, @item2, @item3 = create_list(:memex_project_item, 3, memex_project: @memex)
    @request_id = SecureRandom.uuid
  end

  setup do
    @index = Elastomer::Indexes::MemexProjectItems.new
    GitHub.context.push(request_id: @request_id)
  end

  context ".perform" do
    test "returns result with success=true when all items updated successfully" do
      enable_feature_flag(:memex_sync_write_to_es, @memex)

      expect_progress_messages([40, 80, 100])
      @memex.expects(:notify_memex_channel).with({
        type: MemexProjectItem::BulkUpdater::COMPLETION_MESSAGE_TYPE,
        bulkUpdateSuccess: true,
        actor: { id: @user.id },
        bulkUpdateErrors: [],
        invalidateQueryCache: true,
        requestId: @request_id,
      })

      result = MemexProjectItem::BulkUpdater.perform(
        memex_project: @memex,
        user: @user,
        requests: [
          {
            id: @item1.id,
            memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: "Some new title" } }],
          },
          {
            id: @item2.id,
            memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: "Other title" } }],
          },
        ].map { |params| MemexProjectItem::BulkUpdater::UpdateRequest.build(params) },
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

      expect_progress_messages([80, 100])
      @memex.expects(:notify_memex_channel).with({
        type: MemexProjectItem::BulkUpdater::COMPLETION_MESSAGE_TYPE,
        bulkUpdateSuccess: false,
        actor: { id: @user.id },
        bulkUpdateErrors: [{ memexProjectItemId: @item1.id, message: "o noes and dear me" }],
        invalidateQueryCache: nil,
        requestId: @request_id,
      })

      result = MemexProjectItem::BulkUpdater.perform(
        memex_project: @memex,
        user: @user,
        requests: [
          MemexProjectItem::BulkUpdater::UpdateRequest.build(
            {
              id: @item1.id,
              memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: "oops no" } }],
            }
          )
        ],
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
      enable_feature_flag(:memex_sync_write_to_es, @memex)

      original_title = @item1.content.title
      invalid_title = "a" * (Issue::TITLE_BYTESIZE_LIMIT + 1)

      expect_progress_messages([40, 80, 100])
      @memex.expects(:notify_memex_channel).once.with({
        type: MemexProjectItem::BulkUpdater::COMPLETION_MESSAGE_TYPE,
        bulkUpdateSuccess: false,
        actor: { id: @user.id },
        bulkUpdateErrors: [{ memexProjectItemId: @item1.id, message: "Title is too long (maximum is 256 characters)" }],
        invalidateQueryCache: true,
        requestId: @request_id,
      })

      result = MemexProjectItem::BulkUpdater.perform(
        memex_project: @memex,
        user: @user,
        requests: [
          {
            id: @item1.id,
            memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: invalid_title } }],
          },
          {
            id: @item2.id,
            memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: "Some new title" } }],
          },
        ].map { |params| MemexProjectItem::BulkUpdater::UpdateRequest.build(params) },
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

    test "submits a bulk update to Elasticsearch for all items successfully updated in MySQL" do
      enable_feature_flag(:memex_sync_write_to_es, @memex)
      status_field = @memex.memex_project_columns.find(&:status?)&.to_field
      new_value_object = status_field.settings.dig("options", 0).slice("id", "name")
      invalid_value = "xxxxxxx"

      populate_elasticsearch_index!([@item1, @item2, @item3])

      assert_nil elasticsearch_field_value(@item1, status_field)
      refute_equal(new_value_object, elasticsearch_field_value(@item2, status_field))
      refute_equal(new_value_object, elasticsearch_field_value(@item3, status_field))

      result = MemexProjectItem::BulkUpdater.perform(
        memex_project: @memex,
        user: @user,
        requests: [
          {
            id: @item1.id,
            memex_project_column_values: [{ memex_project_column_id: status_field.id, value: invalid_value }],
          },
          {
            id: @item2.id,
            memex_project_column_values: [{ memex_project_column_id: status_field.id, value: new_value_object["id"] }],
          },
          {
            id: @item3.id,
            memex_project_column_values: [{ memex_project_column_id: status_field.id, value: new_value_object["id"] }],
          },
        ].map { |params| MemexProjectItem::BulkUpdater::UpdateRequest.build(params) },
      )

      refute_predicate result, :success?
      assert_equal 1, result.total_failed_items
      assert_equal 2, result.total_updated_items

      assert_nil elasticsearch_field_value(@item1, status_field)
      assert_equal(new_value_object, elasticsearch_field_value(@item2, status_field))
      assert_equal(new_value_object, elasticsearch_field_value(@item3, status_field))
    end

    test "does not update Elasticsearch for each item" do
      enable_feature_flag(:memex_sync_write_to_es, @memex)
      status_field = @memex.memex_project_columns.find(&:status?)&.to_field
      new_value_object = status_field.settings.dig("options", 0).slice("id", "name")

      MemexProjectColumn::Field::Base.any_instance.expects(:update_elasticsearch_field_value).never

      populate_elasticsearch_index!([@item1])

      MemexProjectItem::BulkUpdater.perform(
        memex_project: @memex,
        user: @user,
        requests: [{
          id: @item1.id,
          memex_project_column_values: [{ memex_project_column_id: status_field.id, value: new_value_object["id"] }],
        }].map { MemexProjectItem::BulkUpdater::UpdateRequest.build(_1) },
      )
    end

    test "indicates that the client query cache should be invalidated when the bulk update to Elasticsearch succeeds" do
      enable_feature_flag(:memex_sync_write_to_es, @memex)
      status_field = @memex.memex_project_columns.find(&:status?)&.to_field
      new_value_object = status_field.settings.dig("options", 0).slice("id", "name")
      populate_elasticsearch_index!([@item1, @item2, @item3])

      expect_progress_messages([40, 80, 100])
      @memex.expects(:notify_memex_channel).with({
        type: MemexProjectItem::BulkUpdater::COMPLETION_MESSAGE_TYPE,
        bulkUpdateSuccess: true,
        actor: { id: @user.id },
        bulkUpdateErrors: [],
        invalidateQueryCache: true,
        requestId: @request_id,
      })

      result = MemexProjectItem::BulkUpdater.perform(
        memex_project: @memex,
        user: @user,
        requests: [
          {
            id: @item1.id,
            memex_project_column_values: [{ memex_project_column_id: status_field.id, value: new_value_object["id"] }],
          },
          {
            id: @item2.id,
            memex_project_column_values: [{ memex_project_column_id: status_field.id, value: new_value_object["id"] }],
          },
        ].map { |params| MemexProjectItem::BulkUpdater::UpdateRequest.build(params) },
      )

      assert_predicate result, :success?
      assert_predicate result.elasticsearch_result, :succeeded?
    end

    test "does not send websocket notification when notify_channel=false" do
      @memex.expects(:notify_memex_channel).never

      result = MemexProjectItem::BulkUpdater.perform(
        memex_project: @memex,
        user: @user,
        requests: [
          MemexProjectItem::BulkUpdater::UpdateRequest.build({
            id: @item1.id,
            memex_project_column_values: [{ memex_project_column_id: "Title", value: { title: "Some new title" } }],
          }),
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

  private def expect_progress_messages(percentages)
    percentages.each do |percentage|
      @memex.expects(:notify_memex_channel).with({
        type: MemexProjectItem::BulkUpdater::PROGRESS_MESSAGE_TYPE,
        actor: { id: @user.id },
        percentage:,
        requestId: @request_id,
      })
    end
  end
end
