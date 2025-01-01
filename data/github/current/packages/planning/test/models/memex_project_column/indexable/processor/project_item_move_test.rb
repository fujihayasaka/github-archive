# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectItemMoveTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @repo = create(:repository, owner: @actor, has_discussions: true)
    @memex = create(:memex_project, owner: @actor, title: "My Memex Project")
    @issue = create(:issue, repository: @repo,  state: "open")
    @other_item = create(:memex_project_item, memex_project: @memex, priority_numerator: 2, priority_denominator: 1)
    @item = create(:memex_project_item, content: @issue, memex_project: @memex, priority_numerator: 1, priority_denominator: 1)
  end

  setup do
    setup_search
    @index = Elastomer::Indexes::MemexProjectItems.new
  end

  context "#subscriptions" do
    test "invoked when a project item is moved" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ProjectItemMove, "github.memex.v0.MemexProjectItemMove") do
        column = @memex.status_column
        previous_value = column.settings_option_ids.first,
        value = column.settings_option_ids.second,
        @item.move(
          prioritization_options: { position: :top },
          column_value_updates: [{ column:, previous_value:, value: }],
          project_view: @memex.default_view,
          user: @actor,
        )
      end
    end
  end

  context "#message validation" do
    test "passes validation when both item_id and project_id are present" do
      message = project_item_move_message
      assert processor.new(message).valid_message?
    end

    test "does not pass validation when item_id is absent" do
      message = project_item_move_message(item: {})
      refute processor.new(message).valid_message?
    end

    test "does not pass validation when project_id is absent" do
      message = project_item_move_message(project: nil)
      refute processor.new(message).valid_message?
    end
  end

  context "#matching elasticsearch documents" do
    test "matches when the document exists" do
      populate_elasticsearch_index!([@item])
      message = project_item_move_message
      assert processor.new(message).matching_elasticsearch_documents?
    end

    test "does not match when the document does not exist" do
      message = project_item_move_message
      refute processor.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical data present" do
    test "returns true when the model exists" do
      message = project_item_move_message
      assert processor.new(message).canonical_data_present?
    end

    test "returns false when the model no longer exists" do
      populate_elasticsearch_index!([@item])
      message = project_item_move_message
      @item.destroy!
      refute processor.new(message).canonical_data_present?
    end
  end

  context "#update" do
    test "updates when item is moved", es_8_only: true do
      column = @memex.status_column
      previous_value = column.settings_option_ids.first
      value = column.settings_option_ids.second
      @item.set_column_value(column, previous_value, @actor)
      populate_elasticsearch_index!([@item])
      assert_equal previous_value, get_field_value(@item, column).dig("single_select_value", "id")

      reset_hydro

      @item.move(
        prioritization_options: { position: :top },
        column_value_updates: [{ column:, previous_value:, value: }],
        user: @actor,
        project_view: @memex.default_view,
      )

      assert_hydro_messages(count: 1, schema: "github.memex.v0.MemexProjectItemMove")
      assert_hydro_messages(count: 0, schema: "github.memex.v0.MemexProjectColumnValueUpdate")
      assert_hydro_messages(count: 0, schema: "github.memex.v0.ProjectItemMetadataUpdate")

      process_messages!

      @index.refresh
      @item.reload
      assert_equal @item.virtual_priority, get_doc(@item.id)["_source"]["virtual_priority"].to_f
      assert_equal @item.column_value(column, require_prefilled_associations: false), get_field_value(@item, column).dig("single_select_value", "name")
    end

    test "updates when item's priority is updated but no column values are updated", es_8_only: true do
      populate_elasticsearch_index!([@item])
      reset_hydro

      @item.move(
        prioritization_options: { position: :top },
        column_value_updates: [],
        user: @actor,
        project_view: @memex.default_view,
      )

      assert_hydro_messages(count: 1, schema: "github.memex.v0.MemexProjectItemMove")
      assert_hydro_messages(count: 0, schema: "github.memex.v0.MemexProjectColumnValueUpdate")
      assert_hydro_messages(count: 0, schema: "github.memex.v0.ProjectItemMetadataUpdate")

      process_messages!

      @index.refresh
      @item.reload
      assert_equal @item.virtual_priority, get_doc(@item.id)["_source"]["virtual_priority"].to_f
    end

    test "applies an update to an item's priority even if the column value update is a noop", es_8_only: true do
      status_column = @memex.status_column
      previous_status_value = status_column.settings_option_ids.first
      new_status_value = status_column.settings_option_ids.second

      # Simulate a situation in which the column value update for this message is a noop (e.g. because the Hydro
      # message under test arrived out of order and the update has already been applied).
      @item.set_column_value(status_column, new_status_value, @actor)

      old_priority_value = 1.0
      new_priority_value = 3.0

      populate_elasticsearch_index!([@item])
      assert_equal new_status_value, get_field_value(@item, status_column).dig("single_select_value", "id")
      assert_equal old_priority_value, @item.reload.virtual_priority

      reset_hydro

      @item.move(
        prioritization_options: { position: :top },
        column_value_updates: [{ column: status_column, previous_value: previous_status_value, value: new_status_value }],
        user: @actor,
        project_view: @memex.default_view,
      )

      assert_hydro_messages(count: 1, schema: "github.memex.v0.MemexProjectItemMove")
      assert_hydro_messages(count: 0, schema: "github.memex.v0.MemexProjectColumnValueUpdate")
      assert_hydro_messages(count: 0, schema: "github.memex.v0.ProjectItemMetadataUpdate")

      process_messages!

      @index.refresh
      @item.reload
      assert_equal new_priority_value, get_doc(@item.id)["_source"]["virtual_priority"].to_f
    end

    test "applies multiple column value updates for an item", es_8_only: true do
      status_column = @memex.status_column
      previous_status_value = status_column.settings_option_ids.first
      new_status_value = status_column.settings_option_ids.second
      @item.set_column_value(status_column, previous_status_value, @actor)

      assignees_column = @memex.columns.find(&:assignees?)
      previous_assignees_value = nil
      new_assignees_value = [@actor.id]
      @item.set_column_value(assignees_column, previous_assignees_value, @actor)

      old_priority_value = 1.0
      new_priority_value = 3.0

      populate_elasticsearch_index!([@item])

      assert_equal previous_status_value, get_field_value(@item, status_column).dig("single_select_value", "id")
      assert_nil get_field_value(@item, status_column).dig("assignees_value")
      assert_equal old_priority_value, get_doc(@item.id).dig("_source", "virtual_priority").to_f

      reset_hydro

      @item.move(
        prioritization_options: { position: :top },
        column_value_updates: [
          { column: status_column, previous_value: previous_status_value, value: new_status_value },
          { column: assignees_column, previous_value: previous_assignees_value, value: new_assignees_value },
        ],
        user: @actor,
        project_view: @memex.default_view,
      )

      assert_hydro_messages(count: 1, schema: "github.memex.v0.MemexProjectItemMove")
      assert_hydro_messages(count: 0, schema: "github.memex.v0.MemexProjectColumnValueUpdate")
      assert_hydro_messages(count: 0, schema: "github.memex.v0.ProjectItemMetadataUpdate")

      process_messages!

      @index.refresh
      @item.reload

      assert_equal new_status_value, get_field_value(@item, status_column).dig("single_select_value", "id")
      assert_equal new_assignees_value, get_field_value(@item, assignees_column).dig("assignees_value").map { |a| a["id"] }
      assert_equal new_priority_value, get_doc(@item.id).dig("_source", "virtual_priority").to_f
    end

    test "no-ops when values are unchanged", es_8_only: true do
      populate_elasticsearch_index!([@item])
      version = get_doc(@item.id)["_version"]

      reset_hydro
      response = processor.new(project_item_move_message).update(es_client)
      assert response.items.map { |i| T.must(i.update)._version }.all? { _1 == version }
      assert response.items.map { |i| T.must(i.update).result }.all? { _1 == Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop }
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_ids = processor.new(project_item_move_message).project_ids_to_resync_on_failure
    assert_equal [@memex.id], project_ids
  end

  test "provides the correct updated models" do
    assert_same_elements [@item], processor.new(project_item_move_message).updated_models
  end

  private def get_doc(item_id)
    @index.docs.get(type: "memex_project_item", routing: item_id, id: item_id)
  end

  private def get_field_value(item, column)
    get_doc(item.id)["_source"]["field_values"].find { _1["field_slug"] == column.name_slug }
  end

  private def processor
    MemexProjectColumn::Interface::Indexable::Processor::ProjectItemMove
  end

  private def process_messages!
    run_processor(Projects::DenormalizationProcessor.new, allowed_primary_query_count: 0)
  end

  private def project_item_move_message(item: @item, project: @memex)
    column = @memex.status_column
    previous_value = column.settings_option_ids.first
    value = column.settings_option_ids.second
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        project: project.present? ? Hydro::EntitySerializer.memex_project(project) : nil,
        project_item: item.present? ? Hydro::EntitySerializer.memex_project_item(item) : nil,
        project_view: Hydro::EntitySerializer.memex_project_view(@memex.default_view),
        project_column_value_records: Hydro::EntitySerializer.memex_project_column_value_records([
          {
            memex_project_column_id: column.id,
            previous_value:,
            value:,
            project_column: column,
          }
        ]),
        request_context: Hydro::EntitySerializer.request_context({}),
      },
      schema: "hydro.schemas.github.memex.v0.MemexProjectItemMove"
    )
  end
end
