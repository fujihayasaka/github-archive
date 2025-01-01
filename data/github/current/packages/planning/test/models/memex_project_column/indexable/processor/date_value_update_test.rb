# typed: true
# frozen_string_literal: true

require "test_helper"

class DateValueUpdateTest < GitHub::TestCase
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
    @date_field = create(:memex_project_column, data_type: :date, memex_project: @project).to_field
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
      date_value = Date.parse("2023-10-19").strftime("%FT%T%:z")
      column_value = create(:date_memex_project_column_value, column: @date_field, creator: @actor, value: date_value)
      project_item = column_value.memex_project_item
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::DateValueUpdate, "github.memex.v0.MemexProjectColumnValueUpdate") do
        project_item.set_column_value(@date_field, Date.parse("2023-10-20").strftime("%FT%T%:z"), @actor)
      end
    end
  end

  context "#update" do
    test "updates project item doc field_values when a date column value changes", es_8_only: true do
      # arrange
      target_project_item = @issue_items[0]
      control_project_item = @issue_items[1]
      initial_date_value = Date.parse("2023-10-17").strftime("%FT%T%:z")
      initial_value = create(:memex_project_column_value, column: @date_field, value: initial_date_value, item: target_project_item)
      populate_elasticsearch_index!(@issue_items)

      new_value = Date.parse("2023-10-19").strftime("%FT%T%:z")
      target_project_item.set_column_value(@date_field, new_value, @actor)
      message = value_update_message(target_project_item, new_value, initial_value.value)

      # act
      MemexProjectColumn::Interface::Indexable::Processor::DateValueUpdate.new(message).update(es_client)
      index.refresh

      # assert
      target_result = get_doc(target_project_item.id)
      assert_equal field_value(target_result, @date_field), new_value
      control_result = get_doc(control_project_item.id)
      assert_nil field(control_result, @date_field.id)
    end

    test "noops when the date column value already exists in the index", es_8_only: true do
      project_item = create(:memex_project_item, memex_project: @project)
      date_value = Date.parse("2023-10-19").strftime("%FT%T%:z")
      initial_value = create(:memex_project_column_value, column: @date_field, value: date_value, item: project_item)

      populate_elasticsearch_index!([project_item])

      message = value_update_message(project_item, date_value, initial_value.value)

      indexed_document = get_doc(project_item.id)
      expected_result = Elastomer::Interfaces::Api::Update::Response::Result::Noop
      expected_version = indexed_document["_version"]

      response = MemexProjectColumn::Interface::Indexable::Processor::DateValueUpdate.new(message).update(es_client)
      assert_equal expected_result, response.result
      assert_equal expected_version, response._version
    end
  end

  test "provides correct project ids for resyncing on failure" do
    date_value = Date.parse("2023-10-19").strftime("%FT%T%:z")
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_update_message(project_item, date_value)
    processor = MemexProjectColumn::Interface::Indexable::Processor::DateValueUpdate.new(message)
    assert_equal [project_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  test "provides correct updated models" do
    target_project_item = @issue_items[0]
    initial_date_value = Date.parse("2023-10-17").strftime("%FT%T%:z")
    initial_value = create(:memex_project_column_value, column: @date_field, value: initial_date_value, item: target_project_item)
    new_value = Date.parse("2023-10-19").strftime("%FT%T%:z")
    target_project_item.set_column_value(@date_field, new_value, @actor)
    message = value_update_message(target_project_item, new_value, initial_value.value)
    processor = MemexProjectColumn::Interface::Indexable::Processor::DateValueUpdate.new(message)
    assert_same_elements [target_project_item, @date_field], processor.updated_models
  end

  private def value_update_message(item, new_value, previous_value = nil)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        project: Hydro::EntitySerializer.memex_project(@project),
        project_column: Hydro::EntitySerializer.memex_project_column(@date_field),
        project_item: Hydro::EntitySerializer.memex_project_item(item),
        value: new_value, # 2023-10-18T00:00:00+00:00
        previous_value: previous_value, # 2023-10-18T00:00:00+00:00
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      },
      schema: "github.memex.v0.MemexProjectColumnValueUpdate"
    )
  end
end
