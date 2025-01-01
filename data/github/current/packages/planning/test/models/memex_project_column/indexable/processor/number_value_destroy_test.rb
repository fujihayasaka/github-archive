# typed: true
# frozen_string_literal: true

require "test_helper"

class NumberValueDestroyTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @number_field = create(:memex_project_column, memex_project: @project, user_defined: true, data_type: :number).to_field
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked in response to a column value destroy message" do
      column_value = create(:number_memex_project_column_value, column: @number_field, creator: @actor)
      reset_hydro

      assert_consumes(MemexProjectColumn::Indexable::Processor::NumberValueDestroy, "github.memex.v0.MemexProjectColumnValueDestroy") do
        column_value.destroy
      end
    end
  end

  test "passes through canonical data gate when there is no canonical value" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_delete_message(project_item)

    passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::NumberValueDestroy.new(message).canonical_data_present?
    assert passes_through_canonical_data_gate
  end

  test "does not pass through canonical data gate when a new canonical value exists" do
    project_item = create(:memex_project_item, memex_project: @project)
    new_value = 25
    project_item.set_column_value(@number_field, new_value, @actor)
    message = value_delete_message(project_item)

    passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::NumberValueDestroy.new(message).canonical_data_present?
    refute passes_through_canonical_data_gate
  end

  context "#update" do
    test "sets an indexed number field value to null when the canonical value is deleted", es_8_only: true do
      project_item = create(:memex_project_item, memex_project: @project)

      # set a value for the number field
      new_value = 7
      project_item.set_column_value(@number_field, new_value, @actor)
      # check that Elasticsearch has indexed the new value
      populate_elasticsearch_index!([project_item])
      indexed_document = get_doc(project_item.id)
      assert_equal field_value(indexed_document, @number_field), new_value
      # Delete the new value from the project item and send the corresponding hydro message
      project_item.clear_column_value(@number_field, @actor)
      message = value_delete_message(project_item)
      MemexProjectColumn::Indexable::Processor::NumberValueDestroy.new(message).update(es_client)
      index.refresh
      # confirm that the field is no longer set to the new value in Elasticsearch
      result = get_doc(project_item.id)
      refute field(result, @number_field)
    end

    test "noops when the indexed value is null and a number column value destroy is processed", es_8_only: true do
      project_item = create(:memex_project_item, memex_project: @project)
      populate_elasticsearch_index!([project_item])
      number_field = create(:memex_project_column, memex_project: @project, user_defined: true, data_type: :number, name: "Not #{@number_field.name}").to_field
      indexed_document = get_doc(project_item.id)
      refute field(indexed_document, number_field)

      message = value_delete_message(project_item, number_field)
      expected_result = Elastomer::Interfaces::Api::Update::Response::Result::Noop
      expected_version = indexed_document["_version"]
      response = MemexProjectColumn::Indexable::Processor::NumberValueDestroy.new(message).update(es_client)
      assert_equal response.result, expected_result
      assert_equal response._version, expected_version
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_delete_message(project_item)
    processor = MemexProjectColumn::Indexable::Processor::NumberValueDestroy.new(message)
    assert_equal [project_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  private def value_delete_message(item, column = @number_field)
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
