# typed: true
# frozen_string_literal: true

require "test_helper"

class SingleSelectSettingsChangeProcessorTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @project = create(:memex_project, owner: @actor)
    @single_select_field = @project.memex_project_columns.find(&:status?)
    @project_item = create(:memex_project_item, memex_project: @project)
    @project_item_2 = create(:memex_project_item, memex_project: @project)
  end

  setup do
    setup_search
  end

  context "#update" do
    test "updates old values to new values" do
      single_select_option_1 = @single_select_field.settings["options"].first
      single_select_option_2 = @single_select_field.settings["options"].second

      @project_item.set_column_value(@single_select_field, single_select_option_1["id"], @actor)
      # We set a different value on project_item_2 to ensure that it doesn't get unexpectedly updated.
      @project_item_2.set_column_value(@single_select_field, single_select_option_2["id"], @actor)
      populate_elasticsearch_index!([@project_item, @project_item_2])

      message = single_select_settings_change_message(@single_select_field)
      processor = new_processor(message)
      # The processor uses the diffed changes to search for the old option value, so make sure it matches the original
      # value.
      processor.expects(:diff_changes).returns([single_select_option_1.dup])

      # Specify a new name of the option we're changing so that we detect a change is needed.
      single_select_option_1["name"] = "#{single_select_option_1["name"]} and more!"
      @single_select_field.save!

      assert_equal 1, processor.update(es_client).first.updated
    end

    test "noops when the old value matches the new value" do
      single_select_option_1 = @single_select_field.settings["options"].first
      single_select_option_2 = @single_select_field.settings["options"].second

      @project_item.set_column_value(@single_select_field, single_select_option_1["id"], @actor)
      @project_item_2.set_column_value(@single_select_field, single_select_option_2["id"], @actor)

      populate_elasticsearch_index!([@project_item, @project_item_2])

      message = single_select_settings_change_message(@single_select_field)
      processor = new_processor(message)

      # Stub diff_changes to return an option that we know has already been indexed as part of the project_item_2 document.
      # This ensures that the update query will find this document. Then, when we compare this found document with the
      # latest canonical options, nothing has changed, so it should be a noop.
      processor.stubs(:diff_changes).returns([single_select_option_2])

      assert_equal 1, processor.update(es_client).first.noops
    end

    test "deleting an option removes matching field_value of project items" do
      to_be_deleted_id = @single_select_field.settings["options"].first["id"]
      @project_item.set_column_value(@single_select_field, to_be_deleted_id, @actor)
      populate_elasticsearch_index!([@project_item])
      assert field(get_doc(@project_item.id), @single_select_field.id)

      settings = @single_select_field.settings
      updated_settings = settings.deep_dup
      updated_settings["options"].delete_if { _1["id"] == to_be_deleted_id }

      @project.update_column(@single_select_field, settings: updated_settings)

      message = single_select_settings_change_message(@single_select_field)
      response = new_processor(message).update(es_client)
      index.refresh

      refute field(get_doc(@project_item.id), @single_select_field.id)
    end
  end

  context "#project_ids_to_resync_on_failure" do
    test "returns the ID of the project whose single select field changed" do
      single_select_field = @project.memex_project_columns.find(&:status?)
      refute_nil single_select_field

      message = single_select_settings_change_message(single_select_field)

      assert_equal([@project.id], new_processor(message).project_ids_to_resync_on_failure)
    end
  end

  private def single_select_settings_change_message(single_select_field = @single_select_field)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        memex_project: Hydro::EntitySerializer.memex_project(@project),
        memex_project_column: Hydro::EntitySerializer.memex_project_column(single_select_field),
        previous_changes: (single_select_field&.previous_changes.to_json || "{}"),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      },
      schema: "hydro.schemas.github.memex.v1.MemexProjectColumnUpdate"
    )
  end

  private def new_processor(message)
    MemexProjectColumn::Indexable::Processor::SingleSelectSettingsChange.new(message)
  end
end
