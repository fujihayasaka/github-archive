# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueTypeDestroyTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    GitHub.flipper[:issue_types].enable
    @admin = create(:verified_user)
    @organization = create(:organization, admin: @admin)
    @issue_type = @organization.issue_types.find_by!(name: IssueType::DEFAULTS.first[:name])
    @memex_project = create(:memex_project, owner: @organization)
    @repo = create(:repository, owner: @organization)
    @issue = create(:issue, repository: @repo, issue_type: @issue_type)
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
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy, "github.v1.IssueTypeDestroy") do
        @issue_type.destroy!
      end
    end
  end

  context "#project_ids_to_resync_on_failure" do
    test "returns project ids for all project items referencing issue type from message" do
      org_project = create(:memex_project, owner: @organization)
      org_issue_item = create(:memex_project_item, memex_project: org_project, content: @issue)
      user_project = create(:memex_project, owner: @admin)
      user_issue_item = create(:memex_project_item, memex_project: user_project, content: @issue)
      populate_elasticsearch_index!([@issue_item, org_issue_item, user_issue_item])

      message = issue_type_destroy_message(issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      refute_empty org_project.memex_project_columns.issue_type, "Expected organization project to have an issue type column"
      assert_empty user_project.memex_project_columns.issue_type, "Expected user project to not have an issue type column"
      assert_equal [@memex_project.id, org_project.id].sort, processor.project_ids_to_resync_on_failure.sort
    end
  end

  context "#updated_models" do
    test "returns correct updated models" do
      message = issue_type_destroy_message(issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)
      assert_empty processor.updated_models
    end
  end

  context "#update" do
    test "clears indexed issue_type_value when the issue type is destroyed", es_8_only: true do
      issue_without_type = create(:issue, repository: @repo)
      issue_without_type_item = create(:memex_project_item, memex_project: @memex_project, content: issue_without_type)
      @issue_type_field.preload_elasticsearch_document_data([@issue_item, issue_without_type_item])
      populate_elasticsearch_index!([@issue_item, issue_without_type_item])

      # We are manually setting require_prefilled_associations here because the underlying issue_type batch method
      # does not set the underlying association with the batch result. Memex prefiller verifies an association is
      # preloaded by default, otherwise it raises an exception. If we attempt to set the association manually Rubocop
      # complains about using a private Rails API, for this test we need to bypass the prefilled associations
      # requirement.
      refute_nil @issue.issue_type, "Expected issue to have an issue type"
      refute_nil @issue_item.column_value(@issue_type_field, require_prefilled_associations: false), "Expected issue item to have an issue type"
      assert_nil issue_without_type.issue_type, "Expected issue to not have an issue type"
      assert_nil issue_without_type_item.column_value(@issue_type_field, require_prefilled_associations: false), "Expected issue item to not have an issue type"

      @issue_type.destroy!
      message = issue_type_destroy_message(issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      assert_changes -> { field(get_doc(@issue_item.id), @issue_type_field.id) }, to: nil do
        assert_no_changes -> { field(get_doc(issue_without_type_item.id), @issue_type_field.id) }, from: nil do
          response = processor.update(es_client)

          assert_equal 1, response.total
          assert_equal 1, response.updated
          assert_equal 0, response.noops
        end
      end
    end

    test "only updates expected documents", es_8_only: true do
      draft_issue = create(:draft_issue)
      draft_issue_item = create(:memex_project_item, content: draft_issue, memex_project: @memex_project)
      new_issue_type = create(:issue_type, owner: @organization)

      populate_elasticsearch_index!([@issue_item, @pull_item, draft_issue_item])

      message = issue_type_destroy_message(issue_type: new_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)
      expected_field_value = {
        "id" => @issue_type.id,
        "name" => @issue_type.name,
      }

      assert_no_changes -> { field_value(get_doc(@issue_item.id), @issue_type_field) }, from: expected_field_value do
        response = processor.update(es_client)

        assert_equal 0, response.total
      end
    end

    test "updates matching issues across projects", es_8_only: true do
      other_memex_project = create(:memex_project, owner: @organization, title: "my other project")
      other_issue_item = create(:memex_project_item, content: @issue, memex_project: other_memex_project)
      other_issue_type_column = other_memex_project.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      other_issue_type_field = other_issue_type_column.to_field
      populate_elasticsearch_index!([@issue_item, other_issue_item])

      @issue_type.destroy!

      message = issue_type_destroy_message(issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      assert_changes -> { field(get_doc(@issue_item.id), @issue_type_field.id) }, to: nil do
        assert_changes -> { field(get_doc(other_issue_item.id), other_issue_type_field.id) }, to: nil do
          response = processor.update(es_client)

          assert_equal 2, response.total
          assert_equal 2, response.updated
        end
      end
    end

    test "clears issue type when it was disabled", es_8_only: true do
      enabled_repository = create(:repository, owner: @organization)
      enabled_issue = create(:issue, repository: enabled_repository, issue_type: @issue_type)
      enabled_issue_item = create(:memex_project_item, memex_project: @memex_project, content: enabled_issue)
      @issue.update!(issue_type: @issue_type)
      @issue_type.update!(enabled: false)

      populate_elasticsearch_index!([@issue_item, enabled_issue_item])

      @issue_type.destroy!

      message = issue_type_destroy_message(issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      entry = field(get_doc(enabled_issue_item.id), @issue_type_field.id)

      assert_no_changes -> { field(get_doc(@issue_item.id), @issue_type_field.id) }, from: nil do
        assert_no_changes -> { field(get_doc(enabled_issue_item.id), @issue_type_field.id) }, from: nil do
          response = processor.update(es_client)

          assert_equal 0, response.total
          assert_equal 0, response.updated
        end
      end
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = issue_type_destroy_message(issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "#valid_message?" do
    test "returns true when the issue type are present" do
      message = issue_type_destroy_message(issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      assert_equal @issue_type.id, message.dig(:issue_type, :id)
      assert_predicate processor, :valid_message?
    end

    test "returns false when the issue type is not present" do
      message = issue_type_destroy_message(issue_type: nil)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      assert_nil message.dig(:issue_type, :id)
      refute_predicate processor, :valid_message?, "Did not expect a valid message when issue type is missing from message"
    end
  end

  context "#canonical_data_present?" do
    test "returns true when the issue type is destroyed" do
      message = issue_type_destroy_message(issue_type: @issue_type.destroy)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      assert_nil IssueType.find_by(id: @issue_type.id)
      assert_predicate processor, :canonical_data_present?
    end

    test "returns false when the issue type is present" do
      message = issue_type_destroy_message(issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      assert_equal @issue_type, IssueType.find_by(id: @issue_type.id)
      refute_predicate processor, :canonical_data_present?
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when issue with issue type referenced in project items has existing elasticsearch documents" do
      populate_elasticsearch_index!([@issue_item])
      message = issue_type_destroy_message(issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      refute_nil @issue.issue_type, "Expected issue to have an issue type"
      refute_empty @issue.memex_project_items, "Expected issue to have memex project items"
      assert_predicate processor, :matching_elasticsearch_documents?
    end

    test "returns false when issue type not referenced in project items" do
      @issue.update!(issue_type: nil)
      populate_elasticsearch_index!([@issue_item])
      message = issue_type_destroy_message(issue_type: @issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy.new(message)

      assert_nil @issue.issue_type, "Expected issue to not have an issue type"
      refute_empty @issue.memex_project_items, "Expected issue to have memex project items"
      refute_predicate processor, :matching_elasticsearch_documents?
    end
  end

  private

  def issue_type_destroy_message(issue_type:)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@admin),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
      },
      schema: "github.v1.IssueTypeDestroy"
    )
  end
end
