# typed: true
# frozen_string_literal: true

require "test_helper"

class ColumnDestroyTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @repo = create(:repository, owner: @actor, has_discussions: true)
    @memex = create(:memex_project, owner: @actor, title: "My Memex Project")
    @field = create(:memex_project_column, memex_project: @memex, name: "My Column").to_field
    @item = create(:memex_project_item, memex_project: @memex)
  end

  setup do
    setup_search
    @index = Elastomer::Indexes::MemexProjectItems.new
  end

  context "#subscriptions" do
    test "invoked when a column is destroyed" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::ColumnDestroy, "github.memex.v1.MemexProjectColumnDestroy") do
        @field.destroy!
      end
    end
  end

  context "#message validation" do
    test "passes validation when both field_id and project_id are present" do
      message = column_destroy_message
      assert processor.new(message).valid_message?
    end

    test "does not pass validation when field_id is absent" do
      message = column_destroy_message(field: {})
      refute processor.new(message).valid_message?
    end

    test "does not pass validation when project_id is absent" do
      message = column_destroy_message(project: nil)
      refute processor.new(message).valid_message?
    end
  end

  context "#matching elasticsearch documents" do
    test "matches when the document exists" do
      create(:memex_project_column_value, column: @field, item: @item)
      populate_elasticsearch_index!([@item])
      message = column_destroy_message
      assert processor.new(message).matching_elasticsearch_documents?
    end

    test "does not match when no matching documents exist" do
      populate_elasticsearch_index!([@item])
      # Create a new column after indexing the first item so that the item has no metadata for that column indexed
      field = create(:memex_project_column, memex_project: @memex, name: "My Column 2").to_field
      message = column_destroy_message(field:)
      refute processor.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical data present" do
    # Note that our terminology is a bit confusing in the case of destroys. To successfully pass through the canonical
    # data gate, we need to verify that the conditions are as we expect for a destroy -- in this case, that the column
    # has in fact been deleted.
    test "returns true when the column has in fact been deleted" do
      message = column_destroy_message
      @field.destroy!
      assert processor.new(message).canonical_data_present?
    end

    test "returns false if the column is still present" do
      message = column_destroy_message
      refute processor.new(message).canonical_data_present?
    end
  end

  context "#update" do
    test "removes columns for any matching docs and ignores others" do
      populate_elasticsearch_index!([@item])
      field = create(:memex_project_column, memex_project: @memex, name: "My Column 2").to_field
      item = create(:memex_project_item, memex_project: @memex)
      create(:memex_project_column_value, column: field, item: item)
      populate_elasticsearch_index!([item])
      assert get_doc(item.id)["_source"]["field_values"].any? { _1["field_id"] == field.id }

      response = processor.new(column_destroy_message(field:)).update(es_client)
      assert_equal 1, response.updated
      refute get_doc(item.id)["_source"]["field_values"].any? { _1["field_id"] == field.id }
    end

    test "noops if there are no matching docs" do
      populate_elasticsearch_index!([@item])
      field = create(:memex_project_column, memex_project: @memex, name: "My Column 2").to_field
      response = processor.new(column_destroy_message(field:)).update(es_client)
      assert_equal 0, response.total
      assert_equal 0, response.updated
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_ids = processor.new(column_destroy_message).project_ids_to_resync_on_failure
    assert_equal [@memex.id], project_ids
  end

  private def processor
    MemexProjectColumn::Indexable::Processor::ColumnDestroy
  end

  private def column_destroy_message(field: @field, project: @memex)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        memex_project: project.present? ? Hydro::EntitySerializer.memex_project(project) : nil,
        memex_project_column: field.present? ? Hydro::EntitySerializer.memex_project_column(field) : nil,
        request_context: Hydro::EntitySerializer.request_context({}),
      },
      schema: "hydro.schemas.github.memex.v1.MemexProjectColumnDestroy"
    )
  end
end
