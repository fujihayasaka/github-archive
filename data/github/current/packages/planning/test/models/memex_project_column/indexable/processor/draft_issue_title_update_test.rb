# typed: true
# frozen_string_literal: true

require "test_helper"

class DraftIssueTitleUpdateTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @draft_issue = create(:draft_issue, title: "github")
    @project_item = create(:memex_project_item, content: @draft_issue, memex_project: @project)
    @title_field = @project.columns.find(&:title?).to_field

    # A title column is required upon a draft issue item creation
    @col = @project.memex_project_columns.named("Title").first
    @col_val = create(
      :memex_project_column_value,
      memex_project_column_id: @col.id,
      memex_project_item_id: @project_item.id,
      value: @project_item.content.title,
      json_value: @project_item.denormalized_title_value
    )
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked on draft issue title update" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate, "github.memex.v0.DraftIssueUpdateTitle") do
        @draft_issue.update!(title: "subscription-test")
      end
    end
  end

  context "#valid_message?" do
    test "returns true when the project, project item and draft issue are still present" do
      message = value_update_message(@draft_issue, new_value: "foo", previous_value: "bar")
      processor = MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate.new(message)

      assert processor.valid_message?
    end

    test "returns false when the project item is not present" do
      message = value_update_message(@draft_issue, item: nil, new_value: "foo", previous_value: "foo")
      processor = MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate.new(message)

      refute processor.valid_message?
    end

    test "returns false when the project is not present" do
      message = value_update_message(@draft_issue, project: nil, new_value: "foo", previous_value: "foo")
      processor = MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate.new(message)

      refute processor.valid_message?
    end

    test "returns false when the project item is in an invalid state" do
      message = value_update_message(nil, item: nil, new_value: "foo", previous_value: "foo")
      processor = MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate.new(message)

      refute processor.valid_message?
    end
  end

  context "#matching_elastisearch_documents?" do
    test "returns true when there is at least one matching document" do
      populate_elasticsearch_index!([@project_item])

      new_title = "bar"
      @draft_issue.update!(title: new_title)
      message = value_update_message(@draft_issue, new_value: new_title, previous_value: @draft_issue.title)
      processor = MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate.new(message)

      assert processor.matching_elasticsearch_documents?
    end

    test "returns false when there are no matching documents" do
      new_title = "bar"

      @draft_issue.update!(title: new_title)

      message = value_update_message(@draft_issue, new_value: new_title, previous_value: @draft_issue.title)
      processor = MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate.new(message)

      refute processor.matching_elasticsearch_documents?
    end
  end

  context "#update" do
    test "updates project item doc field_values when a draft issue title changes", es_8_only: true do
      populate_elasticsearch_index!([@project_item])

      new_title = "bar"
      @draft_issue.update!(title: new_title)
      message = value_update_message(@draft_issue, new_value: new_title, previous_value: @draft_issue.title)

      MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate.new(message).update(es_client)
      index.refresh

      result = get_doc(@project_item.id)
      assert_equal field_value(result, @title_field), new_title
    end

    test "noops when the draft issue title already exists in the index", es_8_only: true do
      populate_elasticsearch_index!([@project_item])

      title = @draft_issue.title
      message = value_update_message(@draft_issue, new_value: title, previous_value: title)
      response = MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate.new(message).update(es_client)

      assert_equal Elastomer::Interfaces::Api::Update::Response::Result::Noop, response.result
    end

    test "noops when DraftIssue is converted to Issue between canonical data validation and the ES update", es_8_only: true do
      populate_elasticsearch_index!([@project_item])

      new_title = "bar"
      message = value_update_message(@draft_issue, new_value: new_title, previous_value: @draft_issue.title)

      response = MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate.new(message).update(es_client)
      MemexProjectItem::ConvertToIssue.call(memex_project_item: @project_item, actor: @actor, repository: @repo)

      result = get_doc(@project_item.id)
      assert_equal field_value(result, @title_field), @draft_issue.title

      assert_equal Elastomer::Interfaces::Api::Update::Response::Result::Noop, response.result
    end
  end

  test "provides correct project ids for resyncing on failure" do
    message = value_update_message(@draft_issue, project: @draft_issue.memex_project)
    processor = MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate.new(message)
    assert_equal [@draft_issue.memex_project.id], processor.project_ids_to_resync_on_failure
  end

  def value_update_message(draft_issue = nil, project: @project, item: @project_item, new_value: nil, previous_value: nil)
    build_message({
      actor: Hydro::EntitySerializer.user(@actor),
      draft_issue: Hydro::EntitySerializer.draft_issue(draft_issue),
      project: Hydro::EntitySerializer.memex_project(project),
      project_item: Hydro::EntitySerializer.memex_project_item(item),
      title: new_value,
      previous_title: previous_value,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    },
    schema: "github.memex.v0.DraftIssueUpdateTitle"
  )
  end
end
