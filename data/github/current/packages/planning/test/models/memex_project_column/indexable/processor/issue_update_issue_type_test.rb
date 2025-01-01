# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueUpdateIssueTypeTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    GitHub.flipper[:issue_types].enable
    @organization = create(:organization)
    @issue_type = @organization.issue_types.find_by!(name: IssueType::DEFAULTS.first[:name])
    @memex_project = create(:memex_project, owner: @organization)
    @repo = create(:repository, owner: @organization)
    @issue = create(:issue, repository: @repo)
    @issue_item = create(:memex_project_item, memex_project: @memex_project, content: @issue)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @pull_item = create(:memex_project_item, memex_project: @memex_project,  content: @pull)
    @draft_issue_item = @memex_project.build_draft_issue(creator: @issue.user, title: "An idea").tap(&:save!)
    @issue_type_column = @memex_project.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
    @issue_type_field = @issue_type_column.to_field
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked when an issue type is updated on an issue" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType, "github.v1.IssueUpdateIssueType") do
        @issue.update(issue_type: @issue_type)
      end
    end
  end

  context "#project_ids_to_resync_on_failure" do
    test "returns project ids for all project items referencing issue from message" do
      project_2 = create(:memex_project, owner: @organization)
      issue_item_2 = create(:memex_project_item, memex_project: project_2, content: @issue)
      @issue.update(issue_type: @issue_type)

      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)
      assert_equal [@memex_project.id, project_2.id].sort, processor.project_ids_to_resync_on_failure.sort
    end
  end

  context "#updated_models" do
    test "returns correct models" do
      project_2 = create(:memex_project, owner: @organization)
      issue_item_2 = create(:memex_project_item, memex_project: project_2, content: @issue)
      @issue.update(issue_type: @issue_type)

      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)
      assert_same_elements [@issue, *@issue.memex_project_items], processor.updated_models
    end
  end

  context "#update" do
    test "updates when the issue type is changed on an issue", es_8_only: true do
      issue_without_type = create(:issue, repository: @repo)
      issue_without_type_item = create(:memex_project_item, memex_project: @memex_project, content: issue_without_type)
      @issue_type_field.preload_elasticsearch_document_data([@issue_item, issue_without_type_item])
      populate_elasticsearch_index!([@issue_item, issue_without_type_item])

      # We are manually setting require_prefilled_associations here because the underlying issue_type batch method
      # does not set the underlying association with the batch result. Memex prefiller verifies an association is
      # preloaded by default, otherwise it raises an exception. If we attempt to set the association manually Rubocop
      # complains about using a private Rails API, for this test we need to bypass the prefilled associations
      # requirement.
      assert_nil @issue.issue_type, "Expected issue to not have an issue type"
      assert_nil @issue_item.column_value(@issue_type_field, require_prefilled_associations: false), "Expected issue item to not have an issue type"
      assert_nil issue_without_type.issue_type, "Expected issue to not have an issue type"
      assert_nil issue_without_type_item.column_value(@issue_type_field, require_prefilled_associations: false), "Expected issue item to not have an issue type"

      # Update an item to have a issue_type
      @issue.update!(issue_type: @issue_type)
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)
      expected_field_value = {
        "id" => @issue_type.id,
        "name" => @issue_type.name,
      }

      refute field(get_doc(@issue_item.id), @issue_type_field.id)
      refute field(get_doc(issue_without_type_item.id), @issue_type_field.id)

      response = processor.update(es_client)
      successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
      assert_equal 1, successes.size
      assert_equal expected_field_value, field_value(get_doc(@issue_item.id), @issue_type_field)
      refute field(get_doc(issue_without_type_item.id), @issue_type_field.id)
    end

    test "clears field values when the issue_type is removed from an issue", es_8_only: true do
      # set up an issue containing a issue_type
      @issue.update!(issue_type: @issue_type)
      populate_elasticsearch_index!([@issue_item])
      assert_equal @issue_type, @issue.issue_type

      # remove the issue_type and emit a hydro message
      @issue.update!(issue_type: nil)

      message = issue_update_issue_type_message(action: "issue.untyped", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_changes -> { field(get_doc(@issue_item.id), @issue_type_field.id) }, to: nil do
        response = processor.update(es_client)
        successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
        assert_equal 1, successes.size
      end
    end

    test "does not index issue type when issue_type is disabled", es_8_only: true do
      # set up an issue containing a issue_type
      @issue.update!(issue_type: @issue_type)
      populate_elasticsearch_index!([@issue_item])
      assert_equal @issue_type, @issue.issue_type

      @issue_type.update!(enabled: false)

      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_no_changes -> { field(get_doc(@issue_item.id), @issue_type_field) }, from: nil do
        response = processor.update(es_client)
        successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
        assert_equal 1, successes.size
      end
    end

    test "issue_type field is cleared if issue_type no longer exists", es_8_only: true do
      # set up an issue containing a issue_type
      @issue.update!(issue_type: @issue_type)
      populate_elasticsearch_index!([@issue_item])
      assert_equal @issue_type, @issue.issue_type

      @issue_type.destroy!

      message = issue_update_issue_type_message(action: "issue.untyped", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_changes -> { field(get_doc(@issue_item.id), @issue_type_field.id) }, to: nil do
        response = processor.update(es_client)
        successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
        assert_equal 1, successes.size
      end
    end

    test "issue_type field is cleared if repository no longer exists", es_8_only: true do
      # set up an issue containing a issue_type
      @issue.update!(issue_type: @issue_type)
      populate_elasticsearch_index!([@issue_item])
      assert_equal @issue_type, @issue.issue_type

      @repo.destroy!

      message = issue_update_issue_type_message(action: "issue.untyped", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_changes -> { field(get_doc(@issue_item.id), @issue_type_field.id) }, to: nil do
        response = processor.update(es_client)
        successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
        assert_equal 1, successes.size
      end
    end

    test "noops when the value of the issue_type has not changed", es_8_only: true do
      # set up an issue containing a issue_type
      @issue.update!(issue_type: @issue_type)
      populate_elasticsearch_index!([@issue_item])

      # assert that attempting to update to the same value is a noop
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)
      initial_field_value = {
        "id" => @issue_type.id,
        "name" => @issue_type.name,
      }

      assert_no_changes -> { field_value(get_doc(@issue_item.id), @issue_type_field) }, from: initial_field_value do
        response = processor.update(es_client)

        noops = response.items.map(&:update).filter_map do |r|
          r&.status == 200 && r&.result&.serialize == "noop"
        end
        assert_equal 1, response.items.size
        assert_equal 1, noops.size
      end
    end

    test "only updates expected documents", es_8_only: true do
      # setup three items
      draft_issue = create(:draft_issue)
      draft_issue_item = create(:memex_project_item, content: draft_issue, memex_project: @memex_project)
      new_issue_type = create(:issue_type, owner: @organization)

      populate_elasticsearch_index!([@issue_item, @pull_item, draft_issue_item])

      @issue.update!(issue_type: new_issue_type)

      # assert that only the issue item was updated
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: new_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)
      expected_field_value = {
        "id" => new_issue_type.id,
        "name" => new_issue_type.name,
      }

      refute field(get_doc(@issue_item.id), @issue_type_field.id)
      response = processor.update(es_client)
      successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
      assert_equal 1, successes.size
      assert field_value(get_doc(@issue_item.id), @issue_type_field), expected_field_value
    end

    test "updates matching issues across projects", es_8_only: true do
      other_memex_project = create(:memex_project, owner: @organization, title: "my other project")
      other_issue_item = create(:memex_project_item, content: @issue, memex_project: other_memex_project)
      other_issue_type_column = other_memex_project.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      other_issue_type_field = other_issue_type_column.to_field
      populate_elasticsearch_index!([@issue_item, other_issue_item])

      new_issue_type = create(:issue_type, owner: @organization)
      @issue.update!(issue_type: new_issue_type)

      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: new_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)
      expected_field_value = {
        "id" => new_issue_type.id,
        "name" => new_issue_type.name,
      }

      refute field(get_doc(@issue_item.id), @issue_type_field.id)
      refute field(get_doc(other_issue_item.id), other_issue_type_field.id)
      response = processor.update(es_client)
      successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
      assert_equal 2, successes.size
      assert_equal field_value(get_doc(@issue_item.id), @issue_type_field), expected_field_value
      assert_equal field_value(get_doc(other_issue_item.id), other_issue_type_field), expected_field_value
    end

    test "does not update project item when issue type is updated when Type column missing", es_8_only: true do
      memex_project_without_type_column = create(:memex_project, owner: @organization, title: "my other project")
      memex_project_without_type_column.memex_project_columns.issue_type.destroy_all
      issue_without_type_column_item = create(:memex_project_item, content: @issue, memex_project: memex_project_without_type_column)
      new_issue_type = create(:issue_type, owner: @organization)
      populate_elasticsearch_index!([@issue_item, issue_without_type_column_item])

      @issue.update!(issue_type: new_issue_type)

      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: new_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)
      expected_field_value = {
        "id" => new_issue_type.id,
        "name" => new_issue_type.name,
      }

      issue_without_type_column_doc = get_doc(issue_without_type_column_item.id)
      issue_type_fields = issue_without_type_column_doc["_source"]["field_values"].select do |field|
        field["field_type"] == MemexProjectColumn::Field::IssueType.data_type
      end
      assert_empty memex_project_without_type_column.memex_project_columns.issue_type, "Expected issue type column to not exist on project"
      assert_empty issue_type_fields, "Did not expect issue_type field to be present in project without Type column"

      assert_no_changes -> { get_doc(issue_without_type_column_item.id) }, from: issue_without_type_column_doc do
        refute field(get_doc(@issue_item.id), @issue_type_field.id)
        response = processor.update(es_client)
        updates = response.items.map(&:update)
        updated = updates.filter_map do |r|
          r&.status == 200 && r&.result&.serialize == "updated"
        end

        assert_equal field_value(get_doc(@issue_item.id), @issue_type_field), expected_field_value
        assert_equal 1, response.items.size
        assert_equal 1, updated.size, "Expected one matching item to have been updated"
      end
    end

    test "raises CanonicalDataMissingError when no related items are found" do
      issue = create(:issue, repository: @repo)
      message = issue_update_issue_type_message(action: "issue.typed", issue: issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_empty issue.memex_project_items, "Expected issue to have no related items"
      assert_raises MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError do
        processor.update(es_client)
      end
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "#valid_message?" do
    test "returns true when the issue and issue type are present" do
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_equal @issue.id, message.dig(:issue, :id)
      assert_predicate processor, :valid_message?
    end

    test "returns false when the issue is not present" do
      message = issue_update_issue_type_message(action: "issue.typed", issue: nil, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_nil message.dig(:issue, :id)
      refute_predicate processor, :valid_message?, "Did not expect a valid message when issue is missing from message"
    end

    test "returns true when the issue type is not present" do
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: nil)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_equal @issue.id, message.dig(:issue, :id)
      assert_nil message.dig(:issue_type, :id)
      assert_predicate processor, :valid_message?, "Expected message to be valid even if issue type is not present in message"
    end

    test "returns true for untyped action when the issue type is present" do
      message = issue_update_issue_type_message(action: "issue.untyped", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_equal @issue.id, message.dig(:issue, :id)
      assert_predicate processor, :valid_message?, "Expected message to be valid for untyped event when issue type is present"
    end
  end

  context "#canonical_data_present?" do
    test "returns true when the issue and issue type are present" do
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_predicate processor, :canonical_data_present?
    end

    test "returns false when the issue is not present" do
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)
      @issue.destroy!

      refute_predicate processor, :canonical_data_present?
    end

    test "returns true when the issue type is not present" do
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)
      @issue_type.destroy!

      assert_predicate processor, :canonical_data_present?
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when issue with issue type referenced in project items has existing elasticsearch documents" do
      @issue.update!(issue_type: @issue_type)
      populate_elasticsearch_index!([@issue_item])
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      refute_nil @issue.issue_type, "Expected issue to have an issue type"
      refute_empty @issue.memex_project_items, "Expected issue to have memex project items"
      assert_predicate processor, :matching_elasticsearch_documents?
    end

    test "returns true when issue without issue type referenced in project items has existing elasticsearch documents" do
      populate_elasticsearch_index!([@issue_item])
      message = issue_update_issue_type_message(action: "issue.typed", issue: @issue, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      assert_nil @issue.issue_type, "Expected issue to not have an issue type"
      refute_empty @issue.memex_project_items, "Expected issue to have memex project items"
      assert_predicate processor, :matching_elasticsearch_documents?
    end

    test "returns false when issue with issue type is not referenced in any project items" do
      # Populate the index with at least one issue with an issue type
      @issue.update!(issue_type: @issue_type)
      populate_elasticsearch_index!([@issue_item])

      # Message for issue2, which is not a memex item
      issue2 = create(:issue, repository: @repo, issue_type: @issue_type)
      message = issue_update_issue_type_message(action: "issue.typed", issue: issue2, issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType.new(message)

      refute_nil issue2.issue_type, "Expected issue2 to have an issue type"
      assert_empty issue2.memex_project_items, "Expected issue2 to not have any memex project items"
      refute_predicate processor, :matching_elasticsearch_documents?
    end
  end

  private

  def issue_update_issue_type_message(action:, issue:, issue_type:)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        repository: Hydro::EntitySerializer.repository(@repo),
        issue: Hydro::EntitySerializer.issue(issue),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
        action:,
      },
      schema: "github.v1.IssueUpdateIssueType"
    )
  end
end
