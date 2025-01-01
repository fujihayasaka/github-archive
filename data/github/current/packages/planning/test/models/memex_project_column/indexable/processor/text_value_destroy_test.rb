# typed: true
# frozen_string_literal: true

require "test_helper"

class TextValueDestroyTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @text_field = create(:memex_project_column, memex_project: @project, user_defined: true, data_type: :text).to_field
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked in response to a column value destroy message" do
      column_value = create(:text_memex_project_column_value, column: @text_field, creator: @actor)
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::TextValueDestroy, "github.memex.v0.MemexProjectColumnValueDestroy") do
        column_value.destroy
      end
    end
  end

  test "passes through canonical data gate when there is no canonical value" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_delete_message(project_item)

    assert MemexProjectColumn::Interface::Indexable::Processor::TextValueDestroy.new(message).canonical_data_present?
  end

  test "does not pass through canonical data gate when a new canonical value exists" do
    project_item = create(:memex_project_item, memex_project: @project)

    value = "bar"
    project_item.set_column_value(@text_field, value, @actor)
    message = value_delete_message(project_item)

    refute MemexProjectColumn::Interface::Indexable::Processor::TextValueDestroy.new(message).canonical_data_present?
  end

  context "#update" do
    test "sets a text field value to null when the canonical value is deleted", es_8_only: true do
      project_item = create(:memex_project_item, memex_project: @project)

      new_value = "bar"
      project_item.set_column_value(@text_field, new_value, @actor)

      populate_elasticsearch_index!([project_item])
      indexed_document = get_doc(project_item.id)
      assert_equal field_value(indexed_document, @text_field), new_value

      project_item.set_column_value(@text_field, "", @actor)
      message = value_delete_message(project_item)
      MemexProjectColumn::Interface::Indexable::Processor::TextValueDestroy.new(message).update(es_client)
      index.refresh

      result = get_doc(project_item.id)
      refute field(result, @text_field)
    end

    test "noops when the indexed value is null and a text column value destroy is processed", es_8_only: true do
      project_item = create(:memex_project_item, memex_project: @project)
      populate_elasticsearch_index!([project_item])
      text_field = create(:memex_project_column, memex_project: @project, user_defined: true, data_type: :text, name: "Not #{@text_field.name}").to_field
      indexed_document = get_doc(project_item.id)
      refute field(indexed_document, text_field)

      message = value_delete_message(project_item, text_field)
      expected_result = Elastomer::Interfaces::Api::Update::Response::Result::Noop
      expected_version = indexed_document["_version"]
      response = MemexProjectColumn::Interface::Indexable::Processor::TextValueDestroy.new(message).update(es_client)
      assert_equal response.result, expected_result
      assert_equal response._version, expected_version
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_delete_message(project_item)
    processor = MemexProjectColumn::Interface::Indexable::Processor::TextValueDestroy.new(message)
    assert_equal [project_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  test "provides correct updated models" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_delete_message(project_item)
    processor = MemexProjectColumn::Interface::Indexable::Processor::TextValueDestroy.new(message)
    assert_empty processor.updated_models
  end

  private def get_doc(item_id)
    index.docs.get(type: "memex_project_item", routing: item_id, id: item_id)
  end

  private def field(doc, field_id)
    doc["_source"]["field_values"].find { |field| field["field_id"] == field_id }
  end

  private def field_value(doc, db_field)
    es_field = field(doc, db_field.id)
    es_field[db_field.class.value_name.to_s]
  end

  private def value_delete_message(item, column = @text_field)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        project: Hydro::EntitySerializer.memex_project(@project),
        project_column: Hydro::EntitySerializer.memex_project_column(column),
        project_item: Hydro::EntitySerializer.memex_project_item(item),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      },
      schema: "github.memex.v1.MemexProjectColumnValueDestroy"
    )
  end
end
