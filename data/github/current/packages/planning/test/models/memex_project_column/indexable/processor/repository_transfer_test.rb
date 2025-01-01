# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryTransferProcessorTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @user_a = create(:verified_user)
    @user_b = create(:verified_user)
    @repo = create(:repository, owner: @user_a)
    @repo.add_member(@user_b)
    @org_a = create(:organization, admin: @user_a)
    @project = create(:memex_project, owner: @user_a, title: "test project")
    @issue = create(:issue, repository: @repo,  state: "open", assignee: @user_b)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked on repository transferred event" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer, "github.repositories.v1.Transferred") do
        message = {
          repository_id: @repo.id,
          previous_owner: Hydro::EntitySerializer.user(@user_a),
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

  context "#matching_elasticsearch_documents?" do
    test "returns true when there is at least one memex project item document in elasticsearch matches by repository" do
      project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_a,
        previous_owner: @repo.owner
      )

      assert MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no memex project item documents in elasticsearch matching the repository" do
      project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      new_repo = create(:repository, owner: @user_a)

      message = repository_transferred_message(
        repository: new_repo,
        new_owner: @org_a,
        previous_owner: @repo.owner
      )

      refute MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical data fetching" do
    test "returns true when the model is present" do
      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_a,
        previous_owner: @repo.owner
      )

      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the model is not present" do
      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_a,
        previous_owner: @repo.owner
      )
      @repo.delete
      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end

  context "#update" do
    test "updates PRs and Issues repository fields when a public repository is transferred" do
      # arrange
      issue_project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      pull_project_item = create(:memex_project_item, content: @pull, memex_project: @project)
      populate_elasticsearch_index!([issue_project_item, pull_project_item])

      # act
      @repo.transfer_ownership_to(@org_a, actor: @user_a, new_name: "renamed_repository")
      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_a,
        previous_owner: @repo.owner
      )
      response = MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer.new(message).update(es_client)
      @index.refresh

      # assert
      results = @index.search_all({ "query": { "match_all": {} } })
      repository_values = results.dig("hits", "hits")
        .map { |result_item| result_item["_source"] }
        .map { _1["field_values"] }.flatten
        .select { _1["field_type"] == "repository" }
        .map { _1["repository_value"] }

      assert_equal 2, repository_values.count do
        _1["full_name"] == @repo.full_name && _1["id"] == @repo.id && _1["owner_id"] == @repo.owner.id
      end

      assert_equal 2, T.must(response).to_hash[:updated]
    end

    test "updates PRs and Issues repository fields and assignees when a private repository is transferred from a Org to another Org" do
      # arrange
      user_alice = create(:verified_user)
      user_bob = create(:verified_user)
      user_chris = create(:verified_user)
      user_daniel = create(:verified_user)

      org_source = create(:organization, admin: @user_a)
      org_source.add_member(user_alice)
      org_source.add_member(user_bob)
      org_source.add_member(user_chris)

      team_source = create(:team, organization: org_source, name: "team_source")
      team_source.add_member(@user_a)
      team_source.add_member(user_alice)
      team_source.add_member(user_bob)

      org_destination = create(:organization, admin: @user_b)
      org_destination.add_member(@user_a)
      org_destination.add_member(user_bob)
      org_destination.add_member(user_chris)

      team_destination = create(:team, organization: org_destination, name: "team_destination")
      team_destination.add_member(@user_a)
      team_destination.add_member(user_bob)
      team_destination.add_member(user_chris)

      repository_target = create(:private_repository, owner: org_source)
      team_source.add_repository(repository_target, :pull, allow_different_owner: true)
      repository_target.add_member(user_daniel)

      issue_a = create(:issue, repository: repository_target, state: "open", assignees: [user_alice, user_bob, user_daniel])
      issue_b = create(:issue, repository: repository_target, state: "open", assignees: [user_alice, user_chris, user_daniel, @user_a])


      project_item_a = create(:memex_project_item, content: issue_a, memex_project: @project)
      project_item_b = create(:memex_project_item, content: issue_b, memex_project: @project)
      populate_elasticsearch_index!([project_item_a, project_item_b])

      # act
      repository_target.transfer_ownership_to(org_destination, actor: @user_a, target_teams: [team_destination])
      message = repository_transferred_message(
        repository: repository_target,
        new_owner: org_destination,
        previous_owner: org_source
      )
      response = MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer.new(message).update(es_client)
      @index.refresh

      # assert
      results = @index.search_all({ "query": { "match_all": {} } })
      field_values = results.dig("hits", "hits")
        .map { |result_item| result_item["_source"] }
        .map { _1["field_values"] }.flatten
      repository_values = field_values
        .select { _1["field_type"] == "repository" }
        .map { _1["repository_value"] }

      assert_equal 2, repository_values.count do
        _1["full_name"] == @repo.full_name && _1["id"] == @repo.id && _1["owner_id"] == @repo.owner.id
      end

      assignees_values = field_values
        .select { _1["field_type"] == "assignees" }
        .map { _1["assignees_value"] }.flatten

      # assignee not present in the new team of the new org
      assert_equal 0, assignees_values.count { |assignee| assignee["login"] == user_alice.login }
      # assginee that is directly added as a repository collaborator are kept
      assert_equal 2, assignees_values.count { |assignee| assignee["login"] == user_daniel.login }
      # assginee that is directly added as a repository collaborator are kept
      assert_equal 1, assignees_values.count { |assignee| assignee["login"] == user_bob.login }
      assert_equal 1, assignees_values.count { |assignee| assignee["login"] == user_chris.login }

      assert_equal 2, T.must(response).to_hash[:updated]
    end

    test "removes assignees field if no assignees are left after transfer" do
      org = create(:organization, admin: @user_a)
      repo = create(:private_repository, owner: org)
      repo.add_member(@user_b)
      issue = create(:issue, repository: repo, state: "open", assignees: [@user_b])
      item = create(:memex_project_item, content: issue, memex_project: @project)
      populate_elasticsearch_index!([item])

      # act
      repo.remove_member(@user_b, @user_a)
      repo.transfer_ownership_to(@org_a, actor: @user_a, new_name: "renamed_repository")
      message = repository_transferred_message(
        repository: repo,
        new_owner: @org_a,
        previous_owner: repo.owner
      )
      response = MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer.new(message).update(es_client)
      @index.refresh
      assignees_field = @project.memex_project_columns.find(&:assignees?)
      refute field(get_doc(item.id), assignees_field.id)
    end

    test "provides correct project ids for resyncing on failure", es_8_only: true do
      issue_project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      pull_project_item = create(:memex_project_item, content: @pull, memex_project: @project)
      item_in_another_project = create(:memex_project_item, content: @pull)
      populate_elasticsearch_index!([issue_project_item, pull_project_item, item_in_another_project])

      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_a,
        previous_owner: @repo.owner
      )
      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer.new(message)
      assert_equal [issue_project_item.memex_project_id, item_in_another_project.memex_project_id].sort, processor.project_ids_to_resync_on_failure.sort
    end

    test "provides the correct updated models" do
      message = repository_transferred_message(
        repository: @repo,
        new_owner: @org_a,
        previous_owner: @repo.owner
      )

      processor = MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer.new(message)
      assert_same_elements [@repo], processor.updated_models
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
