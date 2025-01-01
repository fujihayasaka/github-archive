# typed: true
# frozen_string_literal: true

require "test_helper"

class TextValueCreateTest < GitHub::TestCase
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
    test "invoked in response to a column value create message" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate, "github.memex.v0.MemexProjectColumnValueCreate") do
        create(:text_memex_project_column_value, column: @text_field, item: @issue_items.first, creator: @actor)
      end
    end
  end

  context "#update" do
    test "creates a new entry in field_values when a text column value changes in ES8", es_8_only: true do
      populate_elasticsearch_index!(@issue_items)
      project_item = @issue_items.first

      indexed_document = get_doc(project_item.id)
      assert_nil field(indexed_document, @text_field.id)

      new_value = "my new text value"
      project_item.set_column_value(@text_field, new_value, @actor)
      message = value_create_message(project_item, new_value)

      MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate.new(message).update(es_client)
      index.refresh

      result = get_doc(project_item.id)
      assert_equal field_value(result, @text_field), new_value
    end

    test "noops when a text column value is created that already exists in the index", es_8_only: true do
      project_item = @issue_items.first
      text_value = "my text value"
      project_item.set_column_value(@text_field, text_value, @actor)

      populate_elasticsearch_index!(@issue_items)

      indexed_document = get_doc(project_item.id)
      assert_equal field_value(indexed_document, @text_field), text_value

      message = value_create_message(project_item, text_value)

      expected_result = Elastomer::Interfaces::Api::Update::Response::Result::Noop
      expected_version = indexed_document["_version"]
      response = MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate.new(message).update(es_client)
      assert_equal response.result, expected_result
      assert_equal response._version, expected_version
    end
  end

  context "#valid_message?" do
    test "returns true when the field data type matches message column data type" do
      project_item = create(:memex_project_item, memex_project: @project)
      message = value_create_message(project_item, "foo", @text_field)
      message_is_valid = MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate.new(message).valid_message?
      assert message_is_valid
    end

    test "returns false when the field data type does not match message column data type" do
      project_item = create(:memex_project_item, memex_project: @project)
      single_select_field = create(:single_select_memex_column, memex_project: @project).to_field
      message = value_create_message(project_item, "foo", single_select_field)
      message_is_valid = MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate.new(message).valid_message?
      refute message_is_valid
    end

    test "returns false when an expected entity is missing" do
      project_item = create(:memex_project_item, memex_project: @project)
      message_without_column = value_create_message(project_item, "foo", nil)
      refute MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate.new(message_without_column).valid_message?

      message_without_project = value_create_message(project_item, "foo", @text_field)
      message_without_project.value[:project] = nil
      refute MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate.new(message_without_project).valid_message?

      message_without_project_item = value_create_message(project_item, "foo", @text_field)
      message_without_project_item.value[:project_item] = nil
      refute MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate.new(message_without_project_item).valid_message?
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_item = create(:memex_project_item, memex_project: @project)
    message = value_create_message(project_item, "foo")
    processor = MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate.new(message)
    assert_equal [project_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  test "provides correct updated models" do
    project_item = @issue_items.first
    new_value = "my new text value"
    project_item.set_column_value(@text_field, new_value, @actor)
    message = value_create_message(project_item, new_value)
    processor = MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate.new(message)
    assert_same_elements [project_item, @text_field], processor.updated_models
  end

  private def value_create_message(item, new_value, field = @text_field)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        project: Hydro::EntitySerializer.memex_project(@project),
        project_column: Hydro::EntitySerializer.memex_project_column(field),
        project_item: Hydro::EntitySerializer.memex_project_item(item),
        value: new_value,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      },
      schema: "github.memex.v0.MemexProjectColumnValueCreate"
    )
  end
end
