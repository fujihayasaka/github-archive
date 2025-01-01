# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryTransferParentIssue < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @org_a = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org_a)
    @user = create(:verified_user)
    @repo.add_member(@user)
    @other_repo = create(:repository, owner: @org_a)
    @other_repo.add_member(@user)
    @org_b = create(:organization, admin: @user)
    @project = create(:memex_project, owner: @user, title: "test project")
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked on repository transferred event" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue, "github.repositories.v1.Transferred") do
        message = {
          repository_id: @repo.id,
          previous_owner: Hydro::EntitySerializer.user(@user),
          new_owner: Hydro::EntitySerializer.user(@org_a),
          previous_name: @repo.name,
          new_name: @repo.name,
          new_visibility: Hydro::EntitySerializer.enum_from_string(@repo.visibility)
        }
        hydro_publisher.publish(
          message,
          schema: "hydro.schemas.github.repositories.v1.Transferred",
          topic: "github.repositories.v1.Transferred"
        )
      end
    end
  end

  context "#project_ids_to_resync" do
    test "returns project ids for sub-issues with a parent belonging to the transferred repo" do
      transferring_repo_parent = create(:issue, repository: @repo,  state: "open", assignee: @user)
      transferring_repo_sub = create(:issue, repository: @repo,  state: "open", assignee: @user)

      transferring_repo_parent.add_sub_issue!(transferring_repo_sub, @user.id)
      transferring_repo_project_item = create(:memex_project_item, content: transferring_repo_sub, memex_project: @project)

      other_project = create(:memex_project, owner: @user, title: "test project")
      other_repo_parent = create(:issue, repository: @other_repo,  state: "open", assignee: @user)
      other_repo_sub = create(:issue, repository: @repo,  state: "open", assignee: @user)
      other_repo_parent.add_sub_issue!(other_repo_sub, @user.id)

      other_repo_project_item = create(:memex_project_item, content: other_repo_sub, memex_project: other_project)

      populate_elasticsearch_index!([transferring_repo_project_item, other_repo_project_item])

      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_b,
        previous_owner: @org_a
      )
      processor = MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue.new(message)

      assert_equal [@project.id], processor.project_ids_to_resync
    end
  end

  context "#update" do
    test "updates nwo_reference when parent issue is updated", es_8_only: true do
      transferring_repo_parent = create(:issue, repository: @repo,  state: "open", assignee: @user)
      transferring_repo_sub = create(:issue, repository: @repo,  state: "open", assignee: @user)
      transferring_repo_parent.add_sub_issue!(transferring_repo_sub, @user.id)
      item_needing_update = create(:memex_project_item, content: transferring_repo_sub, memex_project: @project)

      other_org = create(:organization, admin: @user)
      other_org_repo = create(:repository, owner: other_org)
      other_org_repo.add_member(@user)
      other_org_parent = create(:issue, repository: other_org_repo,  state: "open", assignee: @user)
      other_org_sub = create(:issue, repository: other_org_repo,  state: "open", assignee: @user)
      other_org_parent.add_sub_issue!(other_org_sub, @user.id)
      item_not_needing_update = create(:memex_project_item, content: other_org_sub, memex_project: @project)
      unchanging_field_value = {
        "id" => other_org_parent.id,
        "nwo_reference" => other_org_parent.nwo_reference(nil),
        "title" => other_org_parent.title,
      }

      populate_elasticsearch_index!([item_needing_update, item_not_needing_update])

      original_field_value = {
        "id" => transferring_repo_parent.id,
        "nwo_reference" => transferring_repo_parent.nwo_reference(nil),
        "title" => transferring_repo_parent.title,
      }

      @repo.transfer_ownership_to(@org_b, actor: @user, new_name: "renamed_repository")

      expected_field_value = {
        "id" => transferring_repo_parent.id,
        "nwo_reference" => transferring_repo_parent.nwo_reference(nil),
        "title" => transferring_repo_parent.title,
      }
      # Validate that nwo changes after transfer
      refute original_field_value["nwo_reference"] == expected_field_value["nwo_reference"]

      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_b,
        previous_owner: @org_a
      )
      processor = MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue.new(message)

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
      transferring_repo_parent = create(:issue, repository: @repo,  state: "open", assignee: @user)
      transferring_repo_sub = create(:issue, repository: @repo,  state: "open", assignee: @user)
      transferring_repo_parent.add_sub_issue!(transferring_repo_sub, @user.id)
      # Add parent (and not sub-issue) to the project
      item_needing_update = create(:memex_project_item, content: transferring_repo_parent, memex_project: @project)

      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_b,
        previous_owner: @org_a
      )
      processor = MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue.new(message)

      parent_issue_field = @project.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME).to_field
      assert_no_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        result = processor.update(es_client)

        assert_empty result.updated_memex_ids
      end
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_b,
        previous_owner: @org_a
      )
      processor = MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue.new(message)

      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "#valid_message?" do
    test "returns true when repository_id is present" do
      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_b,
        previous_owner: @org_a
      )

      processor = MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue.new(message)
      assert_predicate processor, :valid_message?
    end

    test "returns false when repository_id is not present" do
      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_b,
        previous_owner: @org_a
      )
      message.value[:repository_id] = nil

      processor = MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue.new(message)
      refute_predicate processor, :valid_message?
    end
  end

  context "#canonical_data_present?" do
    test "returns true when the model is present" do
      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_b,
        previous_owner: @org_a
      )

      processor = MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue.new(message)
      assert_predicate processor, :canonical_data_present?
    end

    test "returns false when the model is not present" do
      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_b,
        previous_owner: @org_a
      )
      @repo.delete
      processor = MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue.new(message)
      refute_predicate processor, :canonical_data_present?
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "always returns true since elasticsearch is not queried for this processor" do
      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_b,
        previous_owner: @org_a
      )
      processor = MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue.new(message)

      assert_predicate processor, :matching_elasticsearch_documents?
    end
  end

  private

  def repository_transferred_message(repository:, new_owner:, previous_owner:)
    build_message(
      {
        repository_id: repository.id,
        previous_owner: Hydro::EntitySerializer.user(previous_owner),
        new_owner: Hydro::EntitySerializer.user(new_owner),
        previous_name: repository.name,
        new_name: repository.name,
        new_visibility: Hydro::EntitySerializer.enum_from_string(repository.visibility),
      },
      schema: "hydro.schemas.github.repositories.v1.Transferred"
    )
  end
end
