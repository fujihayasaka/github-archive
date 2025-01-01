# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRenameProcessorTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @repo = create(:repository, owner: @actor)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @issue = create(:issue, repository: @repo, state: "open")
    @old_repo_name = @repo.name
    @new_repo_name = "#{@old_repo_name}-edited"
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked on repository rename event" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::RepositoryRename, "github.v1.RepositoryRename") do
        @repo.rename(@new_repo_name)
      end
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there is at least one memex project item document in elasticsearch matching the repository" do
      project_item  = create(:memex_project_item, content: @issue, memex_project: @project, repository: @repo)

      populate_elasticsearch_index!([project_item])

      @repo.rename(@new_repo_name)

      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)

      assert MemexProjectColumn::Indexable::Processor::RepositoryRename.new(message).matching_elasticsearch_documents?
    end
  end

  context "#update" do
    test "updates the repository name in elasticsearch" do
      project_item  = create(:memex_project_item, content: @issue, memex_project: @project, repository: @repo)

      populate_elasticsearch_index!([project_item])

      @repo.rename(@new_repo_name)

      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)

      response = MemexProjectColumn::Indexable::Processor::RepositoryRename.new(message).update(es_client)

      assert_equal 1, response.updated
    end
  end

  context "#es_update" do
    test "script's parameter has new name for update" do
      @repo.rename(@new_repo_name)

      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)

      response = MemexProjectColumn::Indexable::Processor::RepositoryRename.new(message).es_update

      assert_equal "#{@actor.display_login}/#{@new_repo_name}", T.must(response.params)[:update_value]
    end
  end

  context "#project_ids_to_resync_on_failure" do
    test "provides correct project ids for resyncing on failure", es_8_only: true do
      project_item_1  = create(:memex_project_item, content: @issue, repository: @repo, memex_project: @project)
      project_item_2  = create(:memex_project_item, content: @issue, repository: @repo)

      issue_from_other_repo = create(:issue, repository: create(:repository))
      project_item_3  = create(:memex_project_item, content: issue_from_other_repo)

      populate_elasticsearch_index!([project_item_1, project_item_2, project_item_3])

      @repo.rename(@new_repo_name)

      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)

      processor = MemexProjectColumn::Indexable::Processor::RepositoryRename.new(message)

      assert_equal [@project.id, project_item_2.memex_project_id].sort, processor.project_ids_to_resync_on_failure.sort
    end
  end

  context "#canonical_data_present?" do
    test "returns true if the repository can be found in the database" do
      project_item  = create(:memex_project_item, content: @issue, memex_project: @project, repository: @repo)

      populate_elasticsearch_index!([project_item])

      @repo.rename(@new_repo_name)

      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)

      canonical_data_is_present = MemexProjectColumn::Indexable::Processor::RepositoryRename.new(message).canonical_data_present?

      assert canonical_data_is_present
    end

    test "returns false if the resitory is deleted" do
      project_item  = create(:memex_project_item, content: @issue, memex_project: @project, repository: @repo)

      populate_elasticsearch_index!([project_item])

      @repo.rename(@new_repo_name)

      message = repository_rename_message(@actor, @repo, @old_repo_name, @new_repo_name)

      @repo.delete

      canonical_data_is_present = MemexProjectColumn::Indexable::Processor::RepositoryRename.new(message).canonical_data_present?

      refute canonical_data_is_present
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
