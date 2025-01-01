# typed: true
# frozen_string_literal: true

require "test_helper"

class NumberValueUpdateTest < GitHub::TestCase
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
    @number_field = create(:memex_project_column, data_type: :number, memex_project: @project).to_field
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
      column_value = create(:number_memex_project_column_value, column: @number_field, item: @issue_items.first, creator: @actor)
      reset_hydro

      assert_consumes(MemexProjectColumn::Indexable::Processor::NumberValueUpdate, "github.memex.v0.MemexProjectColumnValueUpdate") do
        column_value.update(value: column_value.value.to_i + 1)
      end
    end
  end

  context "#update" do
    test "updates project item doc field_values when a number column value changes in ES8", es_8_only: true do
      # arrange
      target_project_item = @issue_items[0]
      control_project_item = @issue_items[1]
      initial_value = create(:memex_project_column_value, column: @number_field, value: 1, item: target_project_item)
      populate_elasticsearch_index!(@issue_items)

      new_value = 2
      target_project_item.set_column_value(@number_field, new_value, @actor)
      message = value_update_message(target_project_item, new_value, initial_value)

      # act
      MemexProjectColumn::Indexable::Processor::NumberValueUpdate.new(message).update(es_client)
      @index.refresh

      # assert
      target_result = get_doc(target_project_item.id)
      assert_equal field_value(target_result, @number_field), new_value
      control_result = get_doc(control_project_item.id)
      assert_nil field(control_result, @number_field.id)
    end

    test "noops when the number column value already exists in the index", es_8_only: true do
      project_item = create(:memex_project_item, memex_project: @project)
      number_value = 10
      initial_value = create(:memex_project_column_value, column: @number_field, value: number_value, item: project_item)

      populate_elasticsearch_index!([project_item])

      message = value_update_message(project_item, number_value, initial_value)

      indexed_document = get_doc(project_item.id)
      expected_result = Elastomer::Interfaces::Api::Update::Response::Result::Noop
      expected_version = indexed_document["_version"]

      response = MemexProjectColumn::Indexable::Processor::NumberValueUpdate.new(message).update(es_client)
      assert_equal expected_result, response.result
      assert_equal expected_version, response._version
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_update_message(project_item, 100)
    processor = MemexProjectColumn::Indexable::Processor::NumberValueUpdate.new(message)
    assert_equal [project_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  private def value_update_message(item, new_value, previous_value = nil)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        project: Hydro::EntitySerializer.memex_project(@project),
        project_column: Hydro::EntitySerializer.memex_project_column(@number_field),
        project_item: Hydro::EntitySerializer.memex_project_item(item),
        value: new_value.to_s,
        previous_value: previous_value&.value.to_s,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      },
      schema: "github.memex.v0.MemexProjectColumnValueUpdate"
    )
  end
end
