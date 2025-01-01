# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamRenameProcessorTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @user = create(:user, :verified)
    @other_user = create(:user, :verified)

    @org = create(:organization, plan: "bronze")
    @org.add_admin(@user)
    @org.add_admin(@other_user)

    @repo = create(:repository, owner: @org, from_example: :review_comment_source)
    @repo.add_member(@user)
    @repo.add_member(@other_user)

    @fork = create(:fork_repository, forker: @user, fork_repo: @repo, from_example: :review_comment_fork)

    @team = create(:team, organization: @org, creator: @user, privacy: :closed)
    @team.add_repository_directly(@repo)

    @other_team = create(:team, organization: @org, creator: @user, privacy: :closed)
    @other_team.add_repository_directly(@repo)

    @project = create(:memex_project, owner: @org, title: "test project")
    @pull_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked on team rename event" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::TeamRename, "github.v1.TeamRename") do
        @team.update!(name: "team-rename-test")
      end
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there is at least one memex project item document in elasticsearch matching the team" do
      @pull_request.request_review_from(actor: @user, reviewers: [@other_user, @team])
      project_item = create(:memex_project_item, content: @pull_request, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      message = team_rename_message(@team, "foo")

      assert MemexProjectColumn::Indexable::Processor::TeamRename.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no memex project item documents in elasticsearch mathing the team" do
      @pull_request.request_review_from(actor: @user, reviewers: [@other_user, @other_team])
      project_item = create(:memex_project_item, content: @pull_request, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      message = team_rename_message(@team, "foo")

      refute MemexProjectColumn::Indexable::Processor::TeamRename.new(message).matching_elasticsearch_documents?
    end
  end

  context "#update" do
    test "updates project item doc field_values across projects when a team is renamed" do
      project_item = create(:memex_project_item, content: @pull_request, memex_project: @project)
      pull_request = create(:pull_request, :disable_disk_access, repository: @repo, head_ref: "#{@fork.user}:topic", user: @user)
      item_in_another_project = create(:memex_project_item, content: pull_request)

      pull_request_two = create(:pull_request, :disable_disk_access, repository: @repo, head_ref: "#{@fork.user}:topic1", user: @user)
      item_in_another_project_two = create(:memex_project_item, content: pull_request_two)

      @pull_request.request_review_from(actor: @user, reviewers: [@other_user, @team])
      pull_request.request_review_from(actor: @user, reviewers: [@other_team, @team])
      pull_request_two.request_review_from(actor: @user, reviewers: [@other_user, @other_team])

      populate_elasticsearch_index!([project_item, item_in_another_project, item_in_another_project_two])

      message = team_rename_message(@team, "foo")
      @team.update(name: "foo")
      response = MemexProjectColumn::Indexable::Processor::TeamRename.new(message).update(es_client)

      assert_equal 2, response.updated
    end

    test "noops if the team name doesn't change" do
      @pull_request.request_review_from(actor: @user, reviewers: [@other_user, @team])
      project_item = create(:memex_project_item, content: @pull_request, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      message = team_rename_message(@team)
      response = MemexProjectColumn::Indexable::Processor::TeamRename.new(message).update(es_client)

      assert_equal 0, response.updated
    end

    test "provides correct project ids for resyncing on failure", es_8_only: true do
      project_item = create(:memex_project_item, content: @pull_request, memex_project: @project)
      pull_request = create(:pull_request, :disable_disk_access, repository: @repo, head_ref: "#{@fork.user}:topic", user: @user)
      item_in_another_project = create(:memex_project_item, content: pull_request)

      @pull_request.request_review_from(actor: @user, reviewers: [@other_user, @team])
      pull_request.request_review_from(actor: @user, reviewers: [@other_user, @team])

      populate_elasticsearch_index!([project_item, item_in_another_project])

      message = team_rename_message(@team, "foo")
      processor = MemexProjectColumn::Indexable::Processor::TeamRename.new(message)
      assert_equal [@project.id, item_in_another_project.memex_project_id].sort, processor.project_ids_to_resync_on_failure.sort
    end
  end

  context "#valid_message?" do
    test "returns true if all criterion are met" do
      message = team_rename_message(@team, "foo")
      processor = MemexProjectColumn::Indexable::Processor::TeamRename.new(message)
      assert processor.valid_message?
    end

    test "returns false if team name hasn't changed" do
      message = team_rename_message(@team, "foo", "foo")
      processor = MemexProjectColumn::Indexable::Processor::TeamRename.new(message)
      refute processor.valid_message?
    end

    test "returns false if team is not present" do
      message = build_message(
        {
          previous_name: "foo",
          current_name: "bar"
        },
        schema: "hydro.schemas.github.v1.TeamRename"
      )

      processor = MemexProjectColumn::Indexable::Processor::TeamRename.new(message)
      refute processor.valid_message?
    end
  end

  context "#canonical_data_present?" do
    test "returns true when team is present" do
      message = team_rename_message(@team)
      assert MemexProjectColumn::Indexable::Processor::TeamRename.new(message).canonical_data_present?
    end

    test "returns false when team is not present" do
      message = team_rename_message(@team)
      @team.delete
      refute MemexProjectColumn::Indexable::Processor::TeamRename.new(message).canonical_data_present?
    end
  end

  private

  def team_rename_message(team, current_name = team.name, previous_name = team.name)
    build_message(
      {
        team: Hydro::EntitySerializer.team(team),
        previous_name: previous_name,
        current_name: current_name
      },
      schema: "hydro.schemas.github.v1.TeamRename"
    )
  end
end
