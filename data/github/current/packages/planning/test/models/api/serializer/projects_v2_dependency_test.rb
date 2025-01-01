# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class ProjectV2SerializersTest < Api::SerializerTestCase
  STATUS_ID = MemexProjectStatus.status_enum_string_to_id("ON_TRACK")
  START_DATE = "2022-01-01"
  TARGET_DATE = "2022-12-31"

  fixtures do
    @item = create(:memex_project_item)
    @project = create(:memex_project)
    @status_update = create(:memex_project_status, memex_project: @project, status_id: STATUS_ID, start_date: START_DATE, target_date: TARGET_DATE)
  end

  # The `test_helpers/api_serializer_helper` file uses method_missing magic to automatically
  # define these methods just-in-time when they are called. We are defining these
  # methods explicitly, so we can hint to Sorbet that these methods exist.
  def projects_v2_item(item)
    method_missing(:projects_v2_item, item)
  end

  def projects_v2(item)
    method_missing(:projects_v2, item)
  end

  def projects_v2_status_update(item)
    method_missing(:projects_v2_status_update, item)
  end

  context "#projects_v2_item_hash" do
    test "serializes the base attributes of a project item" do
      output = projects_v2_item(@item).with_indifferent_access

      assert_equal @item.id, output[:id]
      assert_equal @item.global_relay_id, output[:node_id]
      assert_equal @item.memex_project.global_relay_id, output[:project_node_id]
      assert_equal @item.content.global_relay_id, output[:content_node_id]
      assert_equal @item.content_type, output[:content_type]
      assert_equal @item.creator.login, output[:creator][:login]
      assert_equal @item.created_at.iso8601, output[:created_at]
      assert_equal @item.updated_at.iso8601, output[:updated_at]
      assert_nil output[:archived_at]
    end
  end

  context "#projects_v2_hash" do
    test "serializes the base attributes of a project" do
      output = projects_v2(@project).with_indifferent_access

      assert_equal @project.id, output[:id]
      assert_equal @project.global_relay_id, output[:node_id]
      assert_equal @project.owner.login, output[:owner][:login]
      assert_equal @project.creator.login, output[:creator][:login]
      assert_equal @project.title, output[:title]
      assert_equal @project.description, output[:description]
      assert_equal @project.short_description, output[:short_description]
      assert_equal !!@project.public, output[:public]
      assert_equal @project.number, output[:number]
      assert_equal @project.created_at.iso8601, output[:created_at]
      assert_equal @project.updated_at.iso8601, output[:updated_at]
      assert_nil output[:closed_at]
      assert_nil output[:deleted_at]
      assert_nil output[:deleted_by]
    end
  end

  context "#projects_v2_status_update_hash" do
    test "serializes the base attributes of a status update" do
      output = projects_v2_status_update(@status_update).with_indifferent_access

      assert_equal @status_update.id, output[:id]
      assert_equal @status_update.global_relay_id, output[:node_id]
      assert_equal @status_update.creator.login, output[:creator][:login]
      assert_equal @status_update.body, output[:body]
      assert_equal @status_update.start_date.iso8601, output[:start_date]
      assert_equal @status_update.target_date.iso8601, output[:target_date]
      assert_equal MemexProjectStatus.status_id_to_enum_string(@status_update.status_id), output[:status]
      assert_equal @status_update.created_at.iso8601, output[:created_at]
      assert_equal @status_update.updated_at.iso8601, output[:updated_at]
    end
  end
end
