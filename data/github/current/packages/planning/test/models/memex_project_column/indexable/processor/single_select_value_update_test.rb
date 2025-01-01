# typed: true
# frozen_string_literal: true

require "test_helper"

class SingleSelectValueUpdate < GitHub::TestCase
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
    test "invoked in response to a column value update message" do
      column_value = create(
        :single_select_memex_project_column_value,
        column: @single_select_field,
        item: @issue_items.first,
        creator: @actor,
        value: @single_select_field.settings["options"].first["id"],
        json_value: { id: @single_select_field.settings["options"].first["id"] }
      )
      reset_hydro

      assert_consumes(MemexProjectColumn::Indexable::Processor::SingleSelectValueUpdate, "github.memex.v0.MemexProjectColumnValueUpdate") do
        column_value.update(value: @single_select_field.settings["options"].second["id"])
      end
    end
  end

  context "#update" do
    test "updates project item doc field_values when a single-select column value changes in ES8", es_8_only: true do
      project_item = @issue_items[0]
      column_value = populate_single_select_column_value(project_item) # pre-populate the column with an existing value
      populate_elasticsearch_index!(@issue_items)

      single_select_option = @single_select_field.settings["options"].first
      new_value = single_select_option["id"]
      project_item.set_column_value(@single_select_field, new_value, @actor)
      message = value_update_message(project_item, new_value, column_value)

      MemexProjectColumn::Indexable::Processor::SingleSelectValueUpdate.new(message).update(es_client)
      index.refresh

      result = get_doc(project_item.id)
      assert_equal field_value(result, @single_select_field)["name"], single_select_option["name"]
    end

    test "matching item docs are updated when a single-select column's options change", es_8_only: true do
      project_item_1, project_item_2, project_item_3 = @issue_items

      single_select_option_1 = @single_select_field.settings["options"].first
      single_select_option_2 = @single_select_field.settings["options"].second
      single_select_option_3 = @single_select_field.settings["options"].third

      # pre-populate the columns with an existing value
      column_value_1 = populate_single_select_column_value(project_item_1)
      column_value_2 = populate_single_select_column_value(project_item_2)

      # this item will not be updated and its single select value will remain the same
      populate_single_select_column_value(project_item_3, options_index: 2)

      populate_elasticsearch_index!(@issue_items)

      # change the option name
      new_value = "testing/different!"
      single_select_option_1["name"] = new_value
      @single_select_field.save

      # verify that before running the processor the index shows the old values
      result = get_doc(project_item_1.id)
      refute_equal field_value(result, @single_select_field), single_select_option_1.slice("id", "name")
      result = get_doc(project_item_2.id)
      refute_equal field_value(result, @single_select_field), single_select_option_1.slice("id", "name")
      result = get_doc(project_item_3.id)
      assert_equal field_value(result, @single_select_field)["name"], single_select_option_3["name"]

      # 2 items will have the option we are going to change
      project_item_1.set_column_value(@single_select_field, single_select_option_1["id"], @actor)
      project_item_2.set_column_value(@single_select_field, single_select_option_1["id"], @actor)

      # processes messages for target items
      [
        value_update_message(project_item_1, single_select_option_1["id"], column_value_1),
        value_update_message(project_item_2, single_select_option_1["id"], column_value_2),
      ].each do |message|
        MemexProjectColumn::Indexable::Processor::SingleSelectValueUpdate.new(message).update(es_client)
      end

      index.refresh

      # validate that after running the processor, the 2 matching items have been updated, while the other has not
      result = get_doc(project_item_1.id)
      assert_equal field_value(result, @single_select_field)["name"], new_value
      result = get_doc(project_item_2.id)
      assert_equal field_value(result, @single_select_field)["name"], new_value
      result = get_doc(project_item_3.id)
      assert_equal field_value(result, @single_select_field)["name"], single_select_option_3["name"]
    end

    test "noops when the single-select column value already exists in the index", es_8_only: true do
      project_item = create(:memex_project_item, memex_project: @project)
      column_value = populate_single_select_column_value(project_item) # pre-populate the column with an existing value

      populate_elasticsearch_index!([project_item])

      message = value_update_message(project_item, "foo", column_value)

      indexed_document = get_doc(project_item.id)
      expected_result = Elastomer::Interfaces::Api::Update::Response::Result::Noop
      expected_version = indexed_document["_version"]

      response = MemexProjectColumn::Indexable::Processor::SingleSelectValueUpdate.new(message).update(es_client)
      assert_equal expected_result, response.result
      assert_equal expected_version, response._version
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_update_message(project_item, "foo")
    processor = MemexProjectColumn::Indexable::Processor::SingleSelectValueUpdate.new(message)
    assert_equal [project_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  private def populate_single_select_column_value(project_item, options_index: 1)
    current_value = @single_select_field.settings["options"][options_index]["id"]
    create(:memex_project_column_value, column: @single_select_field, value: current_value, item: project_item)
  end

  private def value_update_message(item, new_value, previous_value = nil)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        project: Hydro::EntitySerializer.memex_project(@project),
        project_column: Hydro::EntitySerializer.memex_project_column(@single_select_field),
        project_item: Hydro::EntitySerializer.memex_project_item(item),
        value: new_value,
        previous_value: previous_value&.value,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      },
      schema: "github.memex.v0.MemexProjectColumnValueUpdate"
    )
  end
end
