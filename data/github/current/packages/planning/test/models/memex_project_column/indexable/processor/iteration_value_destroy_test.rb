# typed: true
# frozen_string_literal: true

require "test_helper"

class IterationValueDestroyTest < GitHub::TestCase
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
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @iteration_field = create(:iteration_memex_column_with_completed_iterations, memex_project: @project).to_field
    @iteration_field_options = @iteration_field.settings_all_iterations
    @issue_items = [
      create(:memex_project_item, content: @open_issue, memex_project: @project),
      create(:memex_project_item, content: @pull, memex_project: @project),
    ]
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked in response to a column value destroy message" do
      column_value = create(
        :memex_project_column_value,
        column: @iteration_field,
        item: @issue_items.first,
        creator: @actor,
        value: @iteration_field_options[0]["id"]
      )
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::IterationValueDestroy, "github.memex.v0.MemexProjectColumnValueDestroy") do
        column_value.destroy
      end
    end
  end

  test "passes through canonical data gate when there is no canonical value" do
    project_item = @issue_items.first
    message = value_delete_message(project_item)

    passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::IterationValueDestroy.new(message).canonical_data_present?
    assert passes_through_canonical_data_gate
  end

  test "does not pass through canonical data gate when a new canonical value exists" do
    project_item = @issue_items.first
    new_value = @iteration_field_options[0]["id"]
    project_item.set_column_value(@iteration_field, new_value, @actor)
    message = value_delete_message(project_item)

    passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::IterationValueDestroy.new(message).canonical_data_present?
    refute passes_through_canonical_data_gate
  end

  context "#update" do
    test "sets an indexed iteration field value to null when the canonical value is deleted", es_8_only: true do
      # arrange
      project_item = @issue_items.first
      iteration_option = @iteration_field_options[0]
      new_value = iteration_option["id"]

      project_item.set_column_value(@iteration_field, new_value, @actor)
      populate_elasticsearch_index!([project_item])

      indexed_document = get_doc(project_item.id)
      assert_equal field_value(indexed_document, @iteration_field), iteration_option.slice("id", "title", "duration", "start_date")

      # act
      project_item.clear_column_value(@iteration_field, @actor)
      message = value_delete_message(project_item)
      MemexProjectColumn::Interface::Indexable::Processor::IterationValueDestroy.new(message).update(es_client)
      index.refresh

      # assert
      result = get_doc(project_item.id)
      refute field(result, @iteration_field)
    end

    test "noops when the indexed value is null and an iteration column value destroy is processed", es_8_only: true do
      # arrange
      project_item = @issue_items.first
      populate_elasticsearch_index!([project_item])
      iteration_field = create(:iteration_memex_column_with_completed_iterations, memex_project: @project, name: "Not #{@iteration_field.name}").to_field
      indexed_document = get_doc(project_item.id)
      refute field(indexed_document, iteration_field)

      # act
      message = value_delete_message(project_item, iteration_field)
      response = MemexProjectColumn::Interface::Indexable::Processor::IterationValueDestroy.new(message).update(es_client)

      # assert
      expected_result = Elastomer::Interfaces::Api::Update::Response::Result::Noop
      expected_version = indexed_document["_version"]
      assert_equal response.result, expected_result
      assert_equal response._version, expected_version
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_item = @issue_items.first
    message = value_delete_message(project_item)
    processor = MemexProjectColumn::Interface::Indexable::Processor::IterationValueDestroy.new(message)
    assert_equal [project_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  test "provides correct updated models" do
    project_item = @issue_items.first
    message = value_delete_message(project_item)
    processor = MemexProjectColumn::Interface::Indexable::Processor::IterationValueDestroy.new(message)
    assert_empty processor.updated_models
  end

  private def value_delete_message(item, column = @iteration_field)
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
