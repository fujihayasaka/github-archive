# typed: true
# frozen_string_literal: true

require "test_helper"

class IterationSettingsChangeTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @project = create(:memex_project, owner: @actor)
    @open_issue = create(:issue, repository: @repo,  state: "open")
    @closed_issue = create(:issue, repository: @repo,  state: "closed")
    @iteration_field = create(:iteration_memex_column_with_completed_iterations, memex_project: @project).to_field
    @open_issue_item = create(:memex_project_item, content: @open_issue, memex_project: @project)
    @closed_issue_item = create(:memex_project_item, content: @closed_issue, memex_project: @project)
    @project_item = create(:memex_project_item, memex_project: @project)
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked in response to a iteration settings changed message" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange, "github.memex.v1.MemexProjectColumnUpdate") do
        @project.update_column(@iteration_field, settings: {
          configuration: {
            start_day: 4,
            duration: 14,
            iterations: [
              id: SecureRandom.hex(4),
              title: "Cycle 1",
              start_date: "2023-12-10",
              duration: 14,
            ],
          }
        })
      end
    end
  end

  context "#valid_message?" do
    test "returns false if project or field ids are missing" do
      message = iteration_settings_update_message(project: nil, project_column: nil)
      message_is_valid = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange.new(message).valid_message?
      refute message_is_valid
    end

    test "returns false when the message refers to a field type that isn't iteration" do
      text_project_column = create(:memex_project_column, data_type: :text, memex_project: @project)
      message = iteration_settings_update_message(project: @project, project_column: text_project_column)
      message_is_valid = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange.new(message).valid_message?
      refute message_is_valid
    end

    test "returns false when iteration field update didn't change its settings" do
      message = iteration_settings_update_message(
        project: @project,
        project_column: @iteration_field,
      )
      message_is_valid = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange.new(message).valid_message?
      refute message_is_valid
    end

    # We expect newly added iterations to be processed by the `IterationValueCreate` processor.
    test "ignores newly added iterations" do
      # arrange
      new_iteration = {
        id: SecureRandom.hex(4),
        title: "New iteration",
        duration: 14,
        start_date: "2030-01-01"
      }
      @iteration_field.settings_iterations << new_iteration
      @project.update_column(@iteration_field)

      message = iteration_settings_update_message(
        project: @project,
        project_column: @iteration_field,
      )

      # act
      message_is_valid = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange.new(message).valid_message?

      # assert
      refute message_is_valid
    end

    test "returns true when an iteration item is updated for an iteration field" do
      # arrange
      updated_iteration = @iteration_field.settings_iterations[0]
      updated_iteration["title"] = "Updated iteration title from test"
      @project.update_column(@iteration_field)
      message = iteration_settings_update_message(
        project: @project,
        project_column: @iteration_field,
      )

      # act
      message_is_valid = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange.new(message).valid_message?

      # assert
      assert message_is_valid
    end

    test "returns true when an iteration item is removed from an iteration field" do
      # arrange
      @iteration_field.settings_iterations.shift
      @project.update_column(@iteration_field)
      message = iteration_settings_update_message(
        project: @project,
        project_column: @iteration_field,
      )

      # act
      message_is_valid = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange.new(message).valid_message?

      # assert
      assert message_is_valid
    end
  end

  context "#canonical_data_present?" do
    test "returns true if the project column can be found in the database" do
      message = iteration_settings_update_message(
        project: @project,
        project_column: @iteration_field,
      )
      canonical_data_is_present = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange
        .new(message)
        .canonical_data_present?
      assert canonical_data_is_present
    end

    test "returns false if the project column cannot be found in the database" do
      message = iteration_settings_update_message(
        project: @project,
        project_column: @iteration_field,
      )
      # simulating an inexistent id (for a deleted column) that is still a valid id (> 0)
      message.value[:memex_project_column][:id] = 999999
      canonical_data_is_present = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange
        .new(message)
        .canonical_data_present?
      refute canonical_data_is_present
    end
  end

  context "#project_ids_to_resync_on_failure" do
    test "returns the single project id from the hydro message" do
      message = iteration_settings_update_message(project: @project, project_column: @iteration_field)
      project_ids = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange
        .new(message)
        .project_ids_to_resync_on_failure

      assert_equal [@project.id], project_ids
    end
  end

  context "#updated_models" do
    test "returns correct models" do
      message = iteration_settings_update_message(project: @project, project_column: @iteration_field)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange.new(message)
      assert_same_elements [@iteration_field], processor.updated_models
    end
  end

  context "#update" do
    test "updating an iteration item updates project items that have that value" do
      # arrange
      to_be_updated_iteration_id = @iteration_field.settings["configuration"]["iterations"][0]["id"]
      @open_issue_item.set_column_value(@iteration_field, to_be_updated_iteration_id, @actor)
      @project_item.set_column_value(@iteration_field, to_be_updated_iteration_id, @actor)

      second_iteration_value = @iteration_field.settings["configuration"]["iterations"][1]["id"]
      @closed_issue_item.set_column_value(@iteration_field, second_iteration_value, @actor)
      populate_elasticsearch_index!([@open_issue_item, @project_item, @closed_issue_item])

      # act
      iteration_settings = @iteration_field.settings
      updated_settings = iteration_settings.deep_dup
      edited_iteration = updated_settings["configuration"]["iterations"]
        .find { |iter| iter["id"] == to_be_updated_iteration_id }
      edited_iteration["title"] = "Updated iteration title for test"
      edited_iteration.delete("title_html")

      @project.update_column(
        @iteration_field,
        settings: updated_settings
      )

      message = iteration_settings_update_message(
        project: @project,
        project_column: @iteration_field,
      )
      response = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange.new(message).update(es_client)
      index.refresh

      # assert
      iteration_values = query_all_documents.map do |item|
        value = item["field_values"].find { |field_value| field_value["field_id"] == @iteration_field.id }
        value && value[MemexProjectColumn::Field::Iteration.value_name]
      end

      # asserting updated iterations are reflected in the denormalized documents
      updated_values = iteration_values.select { |value| value && value["id"] == edited_iteration["id"] }
      updated_values.each do |updated_value|
        assert_equal updated_value["title"], edited_iteration["title"]
      end

      # asserting non-updated iterations are not changed in the denormalized documents
      unchanged_values = iteration_values.select { |value| value && value["id"] != edited_iteration["id"] }
      unchanged_values.each do |unchanged_values|
        refute_equal unchanged_values["title"], edited_iteration["title"]
      end

      assert_equal 2, response.first&.updated
    end

    test "deleting an iteration item removes matching field_value of project items" do
      # arrange
      to_be_deleted_iteration_id = @iteration_field.settings["configuration"]["iterations"][0]["id"]
      @open_issue_item.set_column_value(@iteration_field, to_be_deleted_iteration_id, @actor)
      @project_item.set_column_value(@iteration_field, to_be_deleted_iteration_id, @actor)

      second_iteration_value = @iteration_field.settings["configuration"]["iterations"][1]["id"]
      @closed_issue_item.set_column_value(@iteration_field, second_iteration_value, @actor)
      populate_elasticsearch_index!([@open_issue_item, @project_item, @closed_issue_item])

      # act
      iteration_settings = @iteration_field.settings
      updated_settings = iteration_settings.deep_dup
      updated_settings["configuration"]["iterations"].delete_if { |iter| iter["id"] == to_be_deleted_iteration_id }

      @project.update_column(
        @iteration_field,
        settings: updated_settings
      )

      message = iteration_settings_update_message(
        project: @project,
        project_column: @iteration_field,
      )
      response = MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange.new(message).update(es_client)
      index.refresh

      # assert
      iteration_values = query_all_documents.map do |item|
        value = item["field_values"].find { |field_value| field_value["field_id"] == @iteration_field.id }
        value && value[MemexProjectColumn::Field::Iteration.value_name]
      end.compact!

      # asserting that no existing value is the deleted iteration
      iteration_values.each do |updated_value|
        refute_equal updated_value["id"], to_be_deleted_iteration_id
      end

      assert_equal 2, response.first&.updated
    end
  end

  private def query_all_documents
    results = index.search_all({ "query": { "match_all": {} } })
    results.dig("hits", "hits").map { |result_item| result_item["_source"] }
  end

  private def iteration_settings_update_message(project:, project_column:)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        memex_project: Hydro::EntitySerializer.memex_project(project),
        memex_project_column: Hydro::EntitySerializer.memex_project_column(project_column),
        previous_changes: (project_column&.previous_changes.to_json || "{}"),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      },
      schema: "github.memex.v1.MemexProjectColumnUpdate"
    )
  end
end
