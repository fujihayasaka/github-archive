# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Indexable::Processor::SubIssueParentChangeTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)
    @collaborator = create(:user)
    @repo.add_member(@collaborator)
    @project = create(:memex_project, owner: @owner, title: "test project")
    @parent_issue_field = @project.columns.find(&:parent_issue?).to_field
    @child = create(:issue, repository: @repo, state: "open")
    @parent = create(:issue, repository: @repo, state: "open")
    @child_item = create(:memex_project_item, content: @child, memex_project: @project)
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

      populate_elasticsearch_index!([@child_item])
      message = column_update_message(child: @child, parent: @parent, removed: true)

      assert MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no matching documents" do
      other_issue = create(:issue, repository: @repo, state: "open")
      other_issue_item = create(:memex_project_item, content: other_issue, memex_project: @project)

      @parent.add_sub_issue!(@child, @owner.id)

      populate_elasticsearch_index!([@child_item])
      message = column_update_message(child: other_issue, parent: @parent, removed: true)

      refute MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message).matching_elasticsearch_documents?

    end
  end

  context "#canonical data fetching" do
    test "returns true when the target issue is present" do
      message = column_update_message(child: @child, parent: @parent, removed: true)

      passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the target issue is not present" do
      message = column_update_message(child: @child, parent: @parent, removed: true)
      @child.delete
      passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end

  context "#update" do
    test "updates with new parent issue" do
      populate_elasticsearch_index!([@child_item])

      @parent.add_sub_issue!(@child, @owner.id)

      message = column_update_message(child: @child, parent: @parent)
      processor = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message)
      response = processor.update(es_client)

      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      doc = get_doc(@child_item.id)
      assert_equal @parent.nwo_reference(nil), field_value(doc, @parent_issue_field)["nwo_reference"]
    end

    test "noops when parent_issue_column value already exists in the index" do
      # populate ES with the child information
      @parent.add_sub_issue!(@child, @owner.id)
      populate_elasticsearch_index!([@child_item])

      # process a message with the same information
      message = column_update_message(child: @child, parent: @parent)
      response = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message).update(es_client)

      # Check that the result is a noop
      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end

    test "updates with removed parent issue" do
      @parent.add_sub_issue!(@child, @owner.id)
      populate_elasticsearch_index!([@child_item])

      @child.parent_issue_relation.destroy

      message = column_update_message(child: @child, parent: @parent, removed: true)
      processor = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message)
      response = processor.update(es_client)
      assert_equal 1, response.items.size
      doc = get_doc(@child_item.id)
      refute field(doc, @parent_issue_field.id)
    end

    test "only updates expected documents" do
      issue_in_same_repo = create(:issue, repository: @child.repository)
      issue_in_different_repo = create(:issue)
      draft_issue = create(:draft_issue)

      items = [
        create(:memex_project_item, content: issue_in_same_repo, memex_project: @project),
        create(:memex_project_item, content: issue_in_different_repo, memex_project: @project),
        create(:memex_project_item, content: draft_issue, memex_project: @project),
        @child_item
      ]
      relation = @parent.add_sub_issue!(@child, @owner.id)

      populate_elasticsearch_index!(items)

      # Artificially set the draft issue id to be the same as our issue id, to test content type matching
      response = index.docs.update(document_wrapper({ _id: items[2].id, doc: { content: { id: @child.id } } }), { routing: @project.id })
      index.refresh

      relation.destroy!
      message = column_update_message(child: @child, parent: @parent, removed: true)
      response = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message).update(es_client)
      assert_equal 1, response.items.size
    end

    test "updates matching issues across projects" do
      project2 = create(:memex_project, owner: @collaborator, title: "my other project")
      child_item2 = create(:memex_project_item, content: @child, memex_project: project2)

      populate_elasticsearch_index!([@child_item, child_item2])

      @parent.add_sub_issue!(@child, @collaborator.id)

      message = column_update_message(child: @child, parent: @parent)
      processor = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message)
      response = processor.update(es_client)

      assert_equal 2, response.items.size
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = column_update_message(child: @child, parent: @parent)
      processor = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message)
      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "project_ids_to_resync_on_failure" do
    test "provides correct project ids for resyncing on failure" do
      project_2 = create(:memex_project)
      child_item_2 = create(:memex_project_item, memex_project: project_2, content: @child)
      @parent.add_sub_issue!(@child, @collaborator.id)
      message = column_update_message(child: @child, parent: @parent)
      processor = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message)
      assert_equal [@child_item.memex_project_id, child_item_2.memex_project_id].sort, processor.project_ids_to_resync_on_failure.sort
    end
  end

  context "subscriptions" do
    test "invoked when a sub-issue is added to an issue" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::SubIssueParentChange, "github.v1.SubIssueAdd") do
        @parent.add_sub_issue!(@child, @collaborator.id)
      end
    end

    test "invoked when a sub-issue is removed from an issue" do
      relation = @parent.add_sub_issue!(@child, @collaborator.id)
      reset_hydro

      assert_consumes(MemexProjectColumn::Indexable::Processor::SubIssueParentChange, "github.v1.SubIssueRemove") do
        relation.destroy
      end
    end
  end

  context "valid_message?" do
    test "returns true if all criterion are met" do
      message = column_update_message(child: @child, parent: @parent)
      processor = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message)
      assert processor.valid_message?
    end

    test "returns false if child is not present" do
      message = column_update_message(child: nil, parent: @parent)
      processor = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message)
      refute processor.valid_message?
    end

    test "returns false if parent is not present" do
      message = column_update_message(child: @child, parent: nil)
      processor = MemexProjectColumn::Indexable::Processor::SubIssueParentChange.new(message)
      refute processor.valid_message?
    end
  end

  def column_update_message(child:, parent:, removed: false)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@owner),
        source_issue_repository: child ? Hydro::EntitySerializer.repository(child.repository) : nil,
        target_issue: Hydro::EntitySerializer.issue(child),
        source_issue: parent.present? ? Hydro::EntitySerializer.issue(parent) : nil,
      }.compact,
      schema: "github.v1.SubIssue#{removed ? "Remove" : "Add"}"
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
