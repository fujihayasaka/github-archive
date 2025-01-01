# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculateTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)
    @collaborator = create(:user)
    @repo.add_member(@collaborator)
    @project = create(:memex_project, owner: @owner, title: "test project")
    @sub_issues_progress_field = create(:memex_project_column, data_type: :sub_issues_progress, memex_project: @project).to_field

    @child = create(:issue, repository: @repo, state: "open")
    @parent = create(:issue, repository: @repo, state: "open")
    @parent_item = create(:memex_project_item, content: @parent, memex_project: @project)
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  context "#matching elasticsearch documents" do
    test "returns true when there are matching documents" do
      @parent.add_sub_issue!(@child, @owner.id)
      sub_issue_list = @parent.recalculate_sub_issue_list!

      populate_elasticsearch_index!([@parent_item])
      message = column_update_message(parent: @parent, total: sub_issue_list.total, completed: sub_issue_list.completed)

      assert MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no matching documents" do
      other_issue = create(:issue, repository: @repo, state: "open")
      other_issue_item = create(:memex_project_item, content: other_issue, memex_project: @project)

      @parent.add_sub_issue!(@child, @owner.id)

      populate_elasticsearch_index!([@parent_item])
      message = column_update_message(parent: other_issue)

      refute MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message).matching_elasticsearch_documents?

    end
  end

  context "#canonical data fetching" do
    test "returns true when the source issue is present" do
      message = column_update_message(parent: @parent)

      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the source issue is not present" do
      message = column_update_message(parent: @parent)
      @parent.delete
      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end

  context "#update" do
    test "updates with new sub issue list" do
      populate_elasticsearch_index!([@parent_item])

      @parent.add_sub_issue!(@child, @owner.id)
      sub_issue_list = @parent.recalculate_sub_issue_list!

      message = column_update_message(parent: @parent, total: sub_issue_list.total, completed: sub_issue_list.completed)
      processor = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message)
      response = processor.update(es_client)

      assert_equal response.items.size, 1
      refute_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end

    test "noops when sub_issues_progress_column value already exists in the index" do
      # populate ES with the child information
      @parent.add_sub_issue!(@child, @owner.id)
      sub_issue_list = @parent.recalculate_sub_issue_list!
      populate_elasticsearch_index!([@parent_item])

      # process a message with the same information
      message = column_update_message(parent: @parent, total: sub_issue_list.total, completed: sub_issue_list.completed)
      response = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message).update(es_client)

      # Check that the result is a noop and that the version has not changed
      assert_equal response.items.size, 1
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end

    test "updates with removed sub-issues" do
      @parent.add_sub_issue!(@child, @owner.id)
      @parent.recalculate_sub_issue_list!
      populate_elasticsearch_index!([@parent_item])

      @parent.sub_issues.destroy_all
      @parent.recalculate_sub_issue_list!

      message = column_update_message(parent: @parent)
      processor = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message)
      response = processor.update(es_client)
      assert_equal response.items.size, 1
      refute_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end

    test "only updates expected documents" do
      issue_in_same_repo = create(:issue, repository: @parent.repository)
      issue_in_different_repo = create(:issue)
      draft_issue = create(:draft_issue)

      items = [
        create(:memex_project_item, content: issue_in_same_repo, memex_project: @project),
        create(:memex_project_item, content: issue_in_different_repo, memex_project: @project),
        create(:memex_project_item, content: draft_issue, memex_project: @project),
        @parent_item
      ]
      @parent.add_sub_issue!(@child, @owner.id)
      @parent.recalculate_sub_issue_list!

      populate_elasticsearch_index!(items)

      # Artificially set the draft issue id to be the same as our issue id, to test content type matching
      response = index.docs.update(document_wrapper({ _id: items[2].id, doc: { content: { id: @parent.id } } }), { routing: @project.id })
      index.refresh

      @parent.add_sub_issue!(issue_in_same_repo, @owner.id)
      @parent.reload
      @parent.recalculate_sub_issue_list!

      message = column_update_message(parent: @parent, total: @parent.sub_issue_list.total, completed: @parent.sub_issue_list.completed)
      response = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message).update(es_client)
      assert_equal response.items.size, 1
      refute_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end

    test "updates matching issues across projects" do
      project2 = create(:memex_project, owner: @collaborator, title: "my other project")
      parent_item2 = create(:memex_project_item, content: @parent, memex_project: project2)

      populate_elasticsearch_index!([@parent_item, parent_item2])

      @parent.add_sub_issue!(@child, @collaborator.id)
      sub_issue_list = @parent.recalculate_sub_issue_list!

      message = column_update_message(parent: @parent, total: sub_issue_list.total, completed: sub_issue_list.completed)
      processor = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message)
      response = processor.update(es_client)

      assert_equal response.items.size, 2
      refute_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
      refute_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.second&.update&.result
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = column_update_message(parent: @parent)
      processor = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message)
      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "project_ids_to_resync_on_failure" do
    test "provides correct project ids for resyncing on failure" do
      project_2 = create(:memex_project)
      parent_item_2 = create(:memex_project_item, memex_project: project_2, content: @parent)
      @parent.add_sub_issue!(@child, @collaborator.id)
      sub_issue_list = @parent.recalculate_sub_issue_list!
      message = column_update_message(parent: @parent, total: sub_issue_list.total, completed: sub_issue_list.completed)
      processor = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message)
      assert_same_elements [@parent_item.memex_project_id, parent_item_2.memex_project_id], processor.project_ids_to_resync_on_failure
    end
  end

  context "updated_models" do
    test "returns the correct models" do
      project_2 = create(:memex_project)
      parent_item_2 = create(:memex_project_item, memex_project: project_2, content: @parent)
      @parent.add_sub_issue!(@child, @collaborator.id)
      sub_issue_list = @parent.recalculate_sub_issue_list!
      message = column_update_message(parent: @parent, total: sub_issue_list.total, completed: sub_issue_list.completed)
      processor = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message)
      assert_same_elements [@parent, @parent_item, parent_item_2], processor.updated_models
    end
  end

  context "subscriptions" do
    test "invoked when a sub-issue list is recalculated" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate, "github.v1.SubIssueListRecalculate") do
        @parent.add_sub_issue!(@child, @collaborator.id)
        sub_issue_list = @parent.recalculate_sub_issue_list!
      end
    end
  end

  context "valid_message?" do
    test "returns true if all criterion are met" do
      message = column_update_message(parent: @parent)
      processor = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message)
      assert processor.valid_message?
    end

    test "returns false if source issue is not present" do
      message = column_update_message(parent: nil)
      processor = MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate.new(message)
      refute processor.valid_message?
    end
  end

  def column_update_message(parent:, total: 0, completed: 0)
    build_message(
      {
        total: total,
        completed: completed,
        percent_completed: total.nonzero? ? (completed.to_f / total.to_f * 100).to_i : 0,
        source_issue: Hydro::EntitySerializer.issue(parent),
      }.compact,
      schema: "github.v1.SubIssueListRecalculate"
    )
  end

  private def document_wrapper(body)
    if index.index_running_version_8_plus?
      body
    else
      body.merge({ _type: Elastomer::Adapters::MemexProjectItem.document_type })
    end
  end
end
