# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryIssueTypeChangeTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    GitHub.flipper[:issue_types].enable
    @admin = create(:verified_user)
    @organization = create(:organization, admin: @admin)
    @issue_type = @organization.issue_types.find_by!(name: IssueType::DEFAULTS.first[:name])
    @memex_project = create(:memex_project, owner: @organization)
    @repository = create(:repository, owner: @organization)
    @issue = create(:issue, repository: @repository, issue_type: @issue_type)
    @issue_item = create(:memex_project_item, memex_project: @memex_project, content: @issue)
    @repository_issue_type = create(:repository_issue_type, repository: @repository, issue_type: @issue_type)
    @pull = create(:pull_request, :disable_disk_access, repository: @repository)
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
    test "invoked when a RepositoryIssueType is created" do
      issue_type = create(:issue_type, owner: @organization)
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange, "github.v1.RepositoryIssueTypeCreate") do
        create(:repository_issue_type, repository: @repository, issue_type: issue_type)
      end
    end

    test "invoked when a RepositoryIssueType is updated" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange, "github.v1.RepositoryIssueTypeUpdate") do
        @repository_issue_type.update!(enabled: !@repository_issue_type.enabled)
      end
    end

    test "invoked when a RepositoryIssueType is destroyed" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange, "github.v1.RepositoryIssueTypeDestroy") do
        @repository_issue_type.destroy!
      end
    end
  end

  context "#project_ids_to_resync" do
    test "returns project ids for all project items referencing repository from message" do
      org_project = create(:memex_project, owner: @organization)
      org_issue_item = create(:memex_project_item, memex_project: org_project, content: @issue)
      org_project_without_type_column = create(:memex_project, owner: @organization)
      org_project_without_type_column.memex_project_columns.issue_type.destroy_all
      org_project_without_type_column_issue_item = create(:memex_project_item, memex_project: org_project_without_type_column, content: @issue)
      user_project = create(:memex_project, owner: @admin)
      user_issue_item = create(:memex_project_item, memex_project: user_project, content: @issue)
      populate_elasticsearch_index!([@issue_item, @pull_item, @draft_issue_item, org_issue_item, user_issue_item])

      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)

      assert_empty org_project_without_type_column.memex_project_columns.issue_type, "Expected organization project to not have an issue type column"
      refute_empty org_project.memex_project_columns.issue_type, "Expected organization project to have an issue type column"
      assert_empty user_project.memex_project_columns.issue_type, "Expected user project to not have an issue type column"
      assert_equal [@memex_project.id, org_project.id, user_project.id].sort, processor.project_ids_to_resync.sort
    end
  end

  context "#update" do
    # TODO: Remove / update as a part of https://github.com/github/issues/issues/11515 (@Mattamorphic)
    test "updates issue_type_value enabled field", es_8_only: true do
      issue_without_type = create(:issue, repository: @repository)
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
      assert_predicate @repository_issue_type, :enabled?, "Expected repository issue type to be enabled"

      @repository_issue_type.update!(enabled: false)
      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)
      original_field_value = {
        "id" => @issue_type.id,
        "name" => @issue_type.name,
      }

      entry = field(get_doc(@issue_item.id), @issue_type_field.id)

      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        assert_no_changes -> { entry }, from: entry do
          result = processor.update(es_client)

          assert_equal [@memex_project.id], result.updated_memex_ids
        end
      end
    end

    test "issue_type_value is searchable when RepositoryIssueType does not exist", es_8_only: true do
      @repository_issue_type.destroy!

      populate_elasticsearch_index!([@issue_item])

      refute_nil @issue.issue_type, "Expected issue to have an issue type"
      refute_nil @issue_item.column_value(@issue_type_field, require_prefilled_associations: false), "Expected issue item to have an issue type"
      assert_equal 0, RepositoryIssueType.count

      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)
      expected_field_value = {
        "id" => @issue_type.id,
        "name" => @issue_type.name,
      }

      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        assert_no_changes -> { field_value(get_doc(@issue_item.id), @issue_type_field) }, from: expected_field_value do
          result = processor.update(es_client)

          assert_equal [@memex_project.id], result.updated_memex_ids
        end
      end
    end

    test "issue_type_value is enabled when RepositoryIssueType is enabled", es_8_only: true do
      populate_elasticsearch_index!([@issue_item])

      refute_nil @issue.issue_type, "Expected issue to have an issue type"
      refute_nil @issue_item.column_value(@issue_type_field, require_prefilled_associations: false), "Expected issue item to have an issue type"
      assert_equal [@repository_issue_type], RepositoryIssueType.where(repository: @repository_issue_type.repository), "Expected repository to only have one RepositoryIssueType"
      assert_predicate @repository_issue_type, :enabled?, "Expected repository issue type to be enabled"

      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)
      expected_field_value = {
        "id" => @issue_type.id,
        "name" => @issue_type.name,
      }

      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        assert_no_changes -> { field_value(get_doc(@issue_item.id), @issue_type_field) }, from: expected_field_value do
          result = processor.update(es_client)

          assert_equal [@memex_project.id], result.updated_memex_ids
        end
      end
    end

    # TODO: Remove as a part of https://github.com/github/issues/issues/11515 (@Mattamorphic)
    test "issue_type_value is not disabled when a RepositoryIssueType is disabled", es_8_only: true do
      populate_elasticsearch_index!([@issue_item])

      refute_nil @issue.issue_type, "Expected issue to have an issue type"
      refute_nil @issue_item.column_value(@issue_type_field, require_prefilled_associations: false), "Expected issue item to have an issue type"
      assert_equal [@repository_issue_type], RepositoryIssueType.where(repository: @repository_issue_type.repository), "Expected repository to only have one RepositoryIssueType"
      assert_predicate @repository_issue_type, :enabled?, "Expected repository issue type to be enabled"

      issue_type = create(:issue_type, owner: @organization)
      disabled_repository_issue_type = create(:repository_issue_type, repository: @repository, issue_type: issue_type, enabled: false)
      message = repository_issue_type_message(repository_issue_type: disabled_repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)
      original_field_value = {
        "id" => @issue_type.id,
        "name" => @issue_type.name,
      }

      entry = field(get_doc(@issue_item.id), @issue_type_field.id)

      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        assert_no_changes -> { entry }, from: entry do
          result = processor.update(es_client)

          assert_equal [@memex_project.id], result.updated_memex_ids
        end
      end
    end

    test "updating repository_excluded property to same value is a noop", es_8_only: true do
      issue_without_type = create(:issue, repository: @repository)
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
      assert_predicate @repository_issue_type, :enabled?, "Expected repository issue type to be enabled"

      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)
      expected_field_value = {
        "id" => @issue_type.id,
        "name" => @issue_type.name,
      }

      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        assert_no_changes -> { field_value(get_doc(@issue_item.id), @issue_type_field) }, from: expected_field_value do
          result = processor.update(es_client)

          assert_equal [@memex_project.id], result.updated_memex_ids
        end
      end
    end

    # TODO: Remove as a part of https://github.com/github/issues/issues/11515 (@Mattamorphic)
    test "updates items for issues in excluded repository across projects", es_8_only: true do
      other_memex_project = create(:memex_project, owner: @organization, title: "my other project")
      other_issue_item = create(:memex_project_item, content: @issue, memex_project: other_memex_project)
      other_issue_type_column = other_memex_project.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      other_issue_type_field = other_issue_type_column.to_field
      populate_elasticsearch_index!([@issue_item, other_issue_item])

      @repository_issue_type.update!(enabled: false)
      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)
      original_field_value = {
        "id" => @issue_type.id,
        "name" => @issue_type.name,
      }

      entry = field(get_doc(@issue_item.id), @issue_type_field.id)

      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        assert_no_changes -> { entry }, from: entry do
          result = processor.update(es_client)

          assert_equal [@memex_project.id, other_memex_project.id], result.updated_memex_ids
        end
      end
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)

      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "#valid_message?" do
    test "returns true when the repository is present" do
      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)

      assert_equal @repository.id, message.dig(:repository, :id)
      assert_predicate processor, :valid_message?
    end

    test "returns false when the repository is not present" do
      message = build_message(
        {
          actor: Hydro::EntitySerializer.user(@admin),
          repository: nil,
          issue_type: Hydro::EntitySerializer.issue_type(@issue_type),
        },
        schema: "github.v1.RepositoryIssueTypeCreate",
      )
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)

      assert_nil message.dig(:repository, :id)
      refute_predicate processor, :valid_message?, "Did not expect a valid message when repository is missing from message"
    end
  end

  context "#canonical_data_present?" do
    test "returns true when the repository is present" do
      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)

      assert_equal @repository, Repository.find_by(id: @repository_issue_type.repository_id)
      assert_predicate processor, :canonical_data_present?
    end

    test "returns true when the repository is no longer present" do
      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      @repository.destroy!
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)

      assert_nil Repository.find_by(id: @repository_issue_type.repository_id)
      assert_predicate processor, :canonical_data_present?
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when repository has an issue referenced in a project with an issue type" do
      populate_elasticsearch_index!([@issue_item])
      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)

      refute_nil @issue.issue_type, "Expected issue to have an issue type"
      refute_empty @issue.memex_project_items, "Expected issue to have memex project items"
      assert_predicate processor, :matching_elasticsearch_documents?
    end

    test "returns true when repository has an issue referenced in a project without an issue type" do
      @issue.update!(issue_type: nil)
      populate_elasticsearch_index!([@issue_item])
      message = repository_issue_type_message(repository_issue_type: @repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)

      assert_nil @issue.issue_type, "Expected issue to not have an issue type"
      refute_empty @issue.memex_project_items, "Expected issue to have memex project items"
      assert_predicate processor, :matching_elasticsearch_documents?
    end

    test "returns false when repository does not have an issue in a project" do
      repository = create(:repository, owner: @organization)
      issue = create(:issue, repository: repository, issue_type: @issue_type)
      repository_issue_type = create(:repository_issue_type, repository: repository, issue_type: @issue_type)

      populate_elasticsearch_index!([@issue_item])
      message = repository_issue_type_message(repository_issue_type: repository_issue_type)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange.new(message)

      refute_nil issue.issue_type, "Expected issue to have an issue type"
      assert_empty issue.memex_project_items, "Expected issue to not have any memex project items"
      refute_predicate processor, :matching_elasticsearch_documents?
    end
  end

  private

  def repository_issue_type_message(repository_issue_type:, schema: "github.v1.RepositoryIssueTypeCreate")
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@admin),
        repository: Hydro::EntitySerializer.repository(repository_issue_type.repository),
        issue_type: Hydro::EntitySerializer.issue_type(repository_issue_type.issue_type),
      },
      schema:,
    )
  end
end
