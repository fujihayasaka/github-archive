# typed: true
# frozen_string_literal: true

require "test_helper"

class SingleSelectValueDestroyTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @open_issue = create(:issue, repository: @repo,  state: "open")
    @closed_issue = create(:issue, repository: @repo,  state: "closed")
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @single_select_field = create(:single_select_memex_column, memex_project: @project).to_field
    @issue_items = [
      create(:memex_project_item, content: @open_issue, memex_project: @project),
      create(:memex_project_item, content: @pull, memex_project: @project),
      create(:memex_project_item, content: @closed_issue, memex_project: @project)
    ]
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked in response to a column value destroy message" do
      column_value = create(
        :single_select_memex_project_column_value,
        column: @single_select_field,
        item: @issue_items.first,
        creator: @actor,
        value: @single_select_field.settings["options"].first["id"],
        json_value: { id: @single_select_field.settings["options"].first["id"] }
      )
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueDestroy, "github.memex.v0.MemexProjectColumnValueDestroy") do
        column_value.destroy
      end
    end
  end

  test "passes through canonical data gate when there is no canonical value" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_delete_message(project_item)

    passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueDestroy.new(message).canonical_data_present?
    assert passes_through_canonical_data_gate
  end

  test "does not pass through canonical data gate when a new canonical value exists" do
    project_item = create(:memex_project_item, memex_project: @project)
    single_select_option = @single_select_field.settings["options"].first
    new_value = single_select_option["id"]
    project_item.set_column_value(@single_select_field, new_value, @actor)
    message = value_delete_message(project_item)

    passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueDestroy.new(message).canonical_data_present?
    refute passes_through_canonical_data_gate
  end

  context "#update" do
    test "removes an indexed single select field value when the canonical value is deleted", es_8_only: true do
      project_item = create(:memex_project_item, memex_project: @project)
      single_select_option = @single_select_field.settings["options"].first
      new_value = single_select_option["id"]
      project_item.set_column_value(@single_select_field, new_value, @actor)

      populate_elasticsearch_index!([project_item])
      indexed_document = get_doc(project_item.id)
      assert_equal field_value(indexed_document, @single_select_field), single_select_option.slice("id", "name")

      project_item.set_column_value(@single_select_field, "", @actor)
      message = value_delete_message(project_item)
      MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueDestroy.new(message).update(es_client)
      index.refresh

      result = get_doc(project_item.id)
      refute field(result, @single_select_field)
    end

    test "noops when there is no value in the index and a single-select column value destroy is processed", es_8_only: true do
      project_item = create(:memex_project_item, memex_project: @project)
      populate_elasticsearch_index!([project_item])
      single_select_field = create(:single_select_memex_column, memex_project: @project, name: "Not #{@single_select_field.name}").to_field
      indexed_document = get_doc(project_item.id)
      refute field(indexed_document, single_select_field)

      message = value_delete_message(project_item, single_select_field)
      expected_result = Elastomer::Interfaces::Api::Update::Response::Result::Noop
      expected_version = indexed_document["_version"]
      response = MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueDestroy.new(message).update(es_client)
      assert_equal response.result, expected_result
      assert_equal response._version, expected_version
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_delete_message(project_item)
    processor = MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueDestroy.new(message)
    assert_equal [project_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  test "provides correct updated models" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_delete_message(project_item)
    processor = MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueDestroy.new(message)
    assert_empty processor.updated_models
  end

  private def value_delete_message(item, column = @single_select_field)
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
