# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRenameParentIssue < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @repo = create(:repository, owner: @actor)
    @other_repo = create(:repository, owner: @actor)
    @old_repo_name = @repo.name
    @new_repo_name = "#{@old_repo_name}-edited"
    @project = create(:memex_project, owner: @actor, title: "test project")
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked on repository renamed event" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue, "github.v1.RepositoryRename") do
        @repo.rename(@new_repo_name)
      end
    end
  end

  context "#project_ids_to_resync" do
    test "returns project ids for sub-issues with a parent belonging to the renamed repo" do
      renamed_repo_parent = create(:issue, repository: @repo,  state: "open", assignee: @actor)
      renamed_repo_sub = create(:issue, repository: @repo,  state: "open", assignee: @actor)
      renamed_repo_parent.add_sub_issue!(renamed_repo_sub, @actor.id)
      renamed_repo_project_item = create(:memex_project_item, content: renamed_repo_sub, memex_project: @project)

      other_project = create(:memex_project, owner: @actor, title: "test project")
      other_repo_parent = create(:issue, repository: @other_repo,  state: "open", assignee: @actor)
      other_repo_sub = create(:issue, repository: @other_repo,  state: "open", assignee: @actor)
      other_repo_parent.add_sub_issue!(other_repo_sub, @actor.id)
      other_repo_project_item = create(:memex_project_item, content: other_repo_sub, memex_project: other_project)

      populate_elasticsearch_index!([renamed_repo_project_item, other_repo_project_item])

      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)

      assert_equal [@project.id], processor.project_ids_to_resync
    end
  end

  context "#updated_models" do
    test "returns the correct models" do
      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)
      assert_same_elements [@repo], processor.updated_models
    end
  end

  context "#update" do
    test "updates nwo_reference when parent issue is updated", es_8_only: true do
      renamed_repo_parent = create(:issue, repository: @repo,  state: "open", assignee: @actor)
      renamed_repo_sub = create(:issue, repository: @repo,  state: "open", assignee: @actor)
      renamed_repo_parent.add_sub_issue!(renamed_repo_sub, @actor.id)
      item_needing_update = create(:memex_project_item, content: renamed_repo_sub, memex_project: @project)

      other_parent = create(:issue, repository: @other_repo,  state: "open", assignee: @actor)
      other_sub = create(:issue, repository: @other_repo,  state: "open", assignee: @actor)
      other_parent.add_sub_issue!(other_sub, @actor.id)
      item_not_needing_update = create(:memex_project_item, content: other_sub, memex_project: @project)
      unchanging_field_value = {
        "id" => other_parent.id,
        "nwo_reference" => other_parent.name_with_display_owner_reference,
        "title" => other_parent.title,
        "owner_id" => other_parent.owner.id,
      }

      populate_elasticsearch_index!([item_needing_update, item_not_needing_update])

      original_field_value = {
        "id" => renamed_repo_parent.id,
        "nwo_reference" => renamed_repo_parent.name_with_display_owner_reference,
        "title" => renamed_repo_parent.title,
        "owner_id" => renamed_repo_parent.owner.id,
      }

      @repo.rename(@new_repo_name)

      expected_field_value = {
        "id" => renamed_repo_parent.id,
        "nwo_reference" => renamed_repo_parent.name_with_display_owner_reference,
        "title" => renamed_repo_parent.title,
        "owner_id" => renamed_repo_parent.owner.id,
      }
      # Validate that nwo changes after rename
      refute original_field_value["nwo_reference"] == expected_field_value["nwo_reference"]

      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)

      parent_issue_field = @project.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME).to_field
      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        assert_changes -> { field_value(get_doc(item_needing_update.id), parent_issue_field) }, from: original_field_value, to: expected_field_value do
          result = processor.update(es_client)
          assert_equal [@project.id], result.updated_memex_ids
          assert_equal unchanging_field_value, field_value(get_doc(item_not_needing_update.id), parent_issue_field)
        end
      end
    end

    test "does not reindex projects if parent issue is not used", es_8_only: true do
      renamed_repo_parent = create(:issue, repository: @repo,  state: "open", assignee: @actor)
      renamed_repo_sub = create(:issue, repository: @repo,  state: "open", assignee: @actor)
      renamed_repo_parent.add_sub_issue!(renamed_repo_sub, @actor.id)
      # Add parent (and not sub-issue) to the project
      item_needing_update = create(:memex_project_item, content: renamed_repo_parent, memex_project: @project)

      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)

      parent_issue_field = @project.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME).to_field
      assert_no_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        result = processor.update(es_client)

        assert_empty result.updated_memex_ids
      end
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)

      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "#valid_message?" do
    test "returns true when repository_id is present" do
      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)

      assert_predicate processor, :valid_message?
    end

    test "returns false when repository_id is not present" do
      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)
      message.value[:repository][:id] = nil

      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)
      refute_predicate processor, :valid_message?
    end
  end

  context "#canonical_data_present?" do
    test "returns true when the model is present" do
      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)

      assert_predicate processor, :canonical_data_present?
    end

    test "returns false when the model is not present" do
      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)

      @repo.delete
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)
      refute_predicate processor, :canonical_data_present?
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "always returns true since elasticsearch is not queried for this processor" do
      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue.new(message)

      assert_predicate processor, :matching_elasticsearch_documents?
    end
  end

  private

  def repository_rename_message(actor, repo, previous_name, current_name)
    build_message(
      {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(actor),
        repository: Hydro::EntitySerializer.repository(repo),
        previous_name: previous_name,
        current_name: current_name,
      },
      schema: "hydro.schemas.github.v1.RepositoryRename"
    )
  end
end
