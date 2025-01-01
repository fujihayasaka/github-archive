# typed: true
# frozen_string_literal: true

require "test_helper"

class TextValueUpdateTest < GitHub::TestCase
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
    @text_field = create(:memex_project_column, data_type: :text, memex_project: @project).to_field
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
      column_value = create(:text_memex_project_column_value, column: @text_field, item: @issue_items.first, creator: @actor)
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::TextValueUpdate, "github.memex.v0.MemexProjectColumnValueUpdate") do
        column_value.update(value: "#{column_value.value}-updated")
      end
    end
  end

  context "#update" do
    test "updates project item doc field_values when a text column value changes in ES8", es_8_only: true do
      project_item = @issue_items[0]
      initial_value = create(:memex_project_column_value, column: @text_field, value: "my text value", item: project_item)
      populate_elasticsearch_index!(@issue_items)

      new_value = "an updated text value"
      project_item.set_column_value(@text_field, new_value, @actor)
      message = value_update_message(project_item, new_value, initial_value)

      MemexProjectColumn::Interface::Indexable::Processor::TextValueUpdate.new(message).update(es_client)
      index.refresh

      result = get_doc(project_item.id)
      assert_equal field_value(result, @text_field), new_value
    end

    test "noops when the text column value already exists in the index", es_8_only: true do
      project_item = create(:memex_project_item, memex_project: @project)
      initial_value = create(:memex_project_column_value, column: @text_field, value: "my text value", item: project_item)

      populate_elasticsearch_index!([project_item])

      message = value_update_message(project_item, "a new value", initial_value)

      indexed_document = get_doc(project_item.id)
      expected_result = Elastomer::Interfaces::Api::Update::Response::Result::Noop
      expected_version = indexed_document["_version"]

      response = MemexProjectColumn::Interface::Indexable::Processor::TextValueUpdate.new(message).update(es_client)
      assert_equal expected_result, response.result
      assert_equal expected_version, response._version
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_update_message(project_item, "foo")
    processor = MemexProjectColumn::Interface::Indexable::Processor::TextValueUpdate.new(message)
    assert_equal [project_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  test "provides correct updated models" do
    project_item = @issue_items[0]
    initial_value = create(:memex_project_column_value, column: @text_field, value: "my text value", item: project_item)
    new_value = "an updated text value"
    project_item.set_column_value(@text_field, new_value, @actor)
    message = value_update_message(project_item, new_value, initial_value)
    processor = MemexProjectColumn::Interface::Indexable::Processor::TextValueUpdate.new(message)
    assert_same_elements [project_item, @text_field], processor.updated_models
  end

  private def value_update_message(item, new_value, previous_value = nil)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        project: Hydro::EntitySerializer.memex_project(@project),
        project_column: Hydro::EntitySerializer.memex_project_column(@text_field),
        project_item: Hydro::EntitySerializer.memex_project_item(item),
        value: new_value,
        previous_value: previous_value&.value,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      },
      schema: "github.memex.v0.MemexProjectColumnValueUpdate"
    )
  end
end
