# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class ProjectSerializersTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers

  temporarily_skip_until_projects_classic_deprecation

  # The `test_helpers/api_serializer_helper` file uses method_missing magic to automatically
  # define these methods just-in-time when they are called. We are defining these
  # methods explicitly, so we can hint to Sorbet that these methods exist.
  def graphql_project(project)
    method_missing(:graphql_project, project)
  end

  def graphql_project_column(column)
    method_missing(:graphql_project_column, column)
  end

  def graphql_project_card(card)
    method_missing(:graphql_project_card, card)
  end

  def project_card(card)
    method_missing(:project_card, card)
  end

  def graphql_team_project(project)
    method_missing(:graphql_team_project, project)
  end

  ProjectQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id: ID!) {
      project: node(id: $id) {
        ...Api::Serializer::ProjectsDependency::ProjectFragment
      }
    }
  GRAPHQL

  ProjectColumnQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id: ID!) {
      column: node(id: $id) {
        ...Api::Serializer::ProjectsDependency::ProjectColumnFragment
      }
    }
  GRAPHQL

  ProjectCardQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id: ID!) {
      card: node(id: $id) {
        ...Api::Serializer::ProjectsDependency::ProjectColumnCardFragment
      }
    }
  GRAPHQL

  TeamProjectsQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id: ID!, $limit: Int!) {
      team: node(id: $id) {
        ... on Team {
          projects(first: $limit) {
            edges {
              ...Api::Serializer::ProjectsDependency::TeamProjectEdgeFragment
            }
          }
        }
      }
    }
  GRAPHQL

  fixtures do
    @viewer = create(:user, login: "viewer")
    disable_feature_flag(ProjectsClassicSunset::SUNSET_GRAPHQL_API_FLAG)
  end

  context "#graphql_project_hash" do
    test "returns the expected project data" do
      creator = create(:user, login: "creator")
      project = create(:project, body: "Here's a description", creator: creator)
      project.reload

      results = Api::App::PlatformClient.query(ProjectQuery, variables: { id: project.global_relay_id })
      output = graphql_project(results.data.project)

      assert_equal project.id, output["id"]
      assert_equal project.name, output["name"]
      assert_equal project.body, output["body"]
      assert_equal project.number, output["number"]
      assert_equal project.state, output["state"]
      assert_equal project.created_at, output["created_at"]
      assert_equal project.updated_at, output["updated_at"]
      assert_equal project.creator.id, output["creator"]["id"]
      assert_equal project.creator.login, output["creator"]["login"]
      assert_equal "User", output["creator"]["type"]
      assert_equal false, output["creator"]["site_admin"]
    end

    test "returns the expected owner URL for a repository-owned project" do
      repo    = create(:repository)
      project = create(:project, owner: repo)

      results = Api::App::PlatformClient.query(ProjectQuery, variables: { id: project.global_relay_id })
      output = graphql_project(results.data.project)

      assert_equal "#{GitHub.api_url}/repos/#{repo.name_with_owner}", output["owner_url"]
    end

    test "returns the expected owner URL for an organization-owned project" do
      org = create(:organization)
      org.add_member(@viewer)

      project = create(:project, owner: org)

      results = Api::App::PlatformClient.query(ProjectQuery, context: { viewer: @viewer }, variables: { id: project.global_relay_id })
      output = graphql_project(results.data.project)

      assert_equal "#{GitHub.api_url}/orgs/#{org.login}", output["owner_url"]
    end

    test "returns a URL" do
      project = create(:project)

      results = Api::App::PlatformClient.query(ProjectQuery, variables: { id: project.global_relay_id })
      output = graphql_project(results.data.project)

      assert_equal "#{GitHub.api_url}/projects/#{project.id}", output["url"]
    end

    test "returns an HTML URL" do
      project = create(:project)

      results = Api::App::PlatformClient.query(ProjectQuery, variables: { id: project.global_relay_id })
      output = graphql_project(results.data.project)

      assert_equal "#{GitHub.url}/#{project.owner.name_with_owner}/projects/#{project.number}", output["html_url"]
    end

    test "returns a columns URL" do
      project = create(:project)

      results = Api::App::PlatformClient.query(ProjectQuery, variables: { id: project.global_relay_id })
      output = graphql_project(results.data.project)

      assert_equal "#{GitHub.api_url}/projects/#{project.id}/columns", output["columns_url"]
    end

    test "payload is valid", temporarily_skip_until_projects_classic_deprecation: true do
      project = create(:project)

      results = Api::App::PlatformClient.query(ProjectQuery, variables: { id: project.global_relay_id })
      output = graphql_project(results.data.project)
      assert output.key?("owner_url")
      assert output.key?("url")
      assert output.key?("html_url")
      assert output.key?("columns_url")

    end
  end

  context "graphql_project_column_hash" do
    test "returns the expected column data" do
      column = create :project_column
      column.reload

      results = Api::App::PlatformClient.query(ProjectColumnQuery, variables: { id: column.global_relay_id })
      output = graphql_project_column(results.data.column)

      assert_equal column.id, output["id"]
      assert_equal column.name, output["name"]
      assert_equal column.created_at, output["created_at"]
      assert_equal column.updated_at, output["updated_at"]
    end

    test "returns a URL", temporarily_skip_until_projects_classic_deprecation: true do
      column = create :project_column

      results = Api::App::PlatformClient.query(ProjectColumnQuery, variables: { id: column.global_relay_id })
      output = graphql_project_column(results.data.column)

      assert_equal "#{GitHub.api_url}/projects/columns/#{column.id}", output["url"]
    end

    test "returns a project URL" do
      column = create :project_column

      results = Api::App::PlatformClient.query(ProjectColumnQuery, variables: { id: column.global_relay_id })
      output = graphql_project_column(results.data.column)

      assert_equal "#{GitHub.api_url}/projects/#{column.project.id}", output["project_url"]
    end

    test "returns a cards URL" do
      column = create :project_column

      results = Api::App::PlatformClient.query(ProjectColumnQuery, variables: { id: column.global_relay_id })
      output = graphql_project_column(results.data.column)

      assert_equal "#{GitHub.api_url}/projects/columns/#{column.id}/cards", output["cards_url"]
    end

    test "payload is valid" do
      column = create :project_column

      results = Api::App::PlatformClient.query(ProjectColumnQuery, variables: { id: column.global_relay_id })
      output = graphql_project_column(results.data.column)
      assert output.key?("url")
      assert output.key?("project_url")
      assert output.key?("cards_url")
      assert output.key?("id")
    end
  end

  context "#graphql_project_card_hash" do
    test "returns the expected card data" do
      card = create(:project_card, note: "do this thing")
      card.reload

      results = Api::App::PlatformClient.query(ProjectCardQuery, variables: { id: card.global_relay_id })
      output = graphql_project_card(results.data.card)

      assert_equal card.id, output["id"]
      assert_equal card.note, output["note"]
      assert_equal card.creator.id, output["creator"]["id"]
      assert_equal card.creator.login, output["creator"]["login"]
      assert_equal card.created_at, output["created_at"]
      assert_equal card.updated_at, output["updated_at"]
    end

    test "returns a content_url that points to the card's content" do
      card = create :project_card
      repo = card.project.owner

      results = Api::App::PlatformClient.query(ProjectCardQuery, variables: { id: card.global_relay_id })
      output = graphql_project_card(results.data.card)

      assert_equal "#{GitHub.api_url}/repos/#{repo.name_with_owner}/issues/#{card.content.number}", output["content_url"]
    end

    test "returns no content_url if the card has no content" do
      card = create(:note_project_card)

      results = Api::App::PlatformClient.query(ProjectCardQuery, variables: { id: card.global_relay_id })
      output = graphql_project_card(results.data.card)

      assert_nil card.content
      refute output.key?(:content_url)
    end

    test "returns no content_url if the card's content is in a deleted repository" do
      org = create(:organization, admin: @viewer)
      project = create(:project, owner: org)
      column = create(:project_column, project: project)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      card = create(:project_card, column: column, content: issue)
      repo.destroy

      results = Api::App::PlatformClient.query(ProjectCardQuery, context: { viewer: @viewer }, variables: { id: card.global_relay_id })
      output = graphql_project_card(results.data.card)

      refute output.key?(:content_url)
    end

    test "returns a URL", temporarily_skip_until_projects_classic_deprecation: true do
      card = create :project_card

      results = Api::App::PlatformClient.query(ProjectCardQuery, variables: { id: card.global_relay_id })
      output = graphql_project_card(results.data.card)

      assert_equal "#{GitHub.api_url}/projects/columns/cards/#{card.id}", output["url"]
    end

    test "returns a column URL" do
      card = create :project_card

      results = Api::App::PlatformClient.query(ProjectCardQuery, variables: { id: card.global_relay_id })
      output = graphql_project_card(results.data.card)

      assert_equal "#{GitHub.api_url}/projects/columns/#{card.column.id}", output["column_url"]
    end

    test "returns a project URL" do
      card = create(:project_card)

      results = Api::App::PlatformClient.query(ProjectCardQuery, variables: { id: card.global_relay_id })
      output = graphql_project_card(results.data.card)

      assert_equal "#{GitHub.api_url}/projects/#{card.project_id}", output["project_url"]
    end

    test "works for a card on an organization-owned project" do
      project = create(:org_project)
      project.owner.add_member(@viewer)

      column = create(:project_column, project: project)
      card = create(:note_project_card, column: column)

      results = Api::App::PlatformClient.query(ProjectCardQuery, context: { viewer: @viewer }, variables: { id: card.global_relay_id })
      output = graphql_project_card(results.data.card)

      assert_equal card.id, output["id"]
    end

    test "payload is valid" do
      card = create(:project_card)
      results = Api::App::PlatformClient.query(ProjectCardQuery, variables: { id: card.global_relay_id })

      output = graphql_project_card(results.data.card)
      assert output.key?("url")
      assert output.key?("project_url")
      assert output.key?("id")
      assert output.key?("node_id")
    end

    test "payload is valid for note card" do
      card = create(:note_project_card)
      results = Api::App::PlatformClient.query(ProjectCardQuery, variables: { id: card.global_relay_id })

      output = graphql_project_card(results.data.card)
      assert output.key?("url")
      assert output.key?("project_url")
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("note")
    end

    test "returns the expected card data for a mannequin card creator" do
      mannequin = create(:mannequin)
      mannequin_card = create(:project_card, creator: mannequin, note: "don't throw an error :)")
      mannequin_card.reload

      results = Api::App::PlatformClient.query(ProjectCardQuery, variables: { id: mannequin_card.global_relay_id })
      output = graphql_project_card(results.data.card)

      assert_equal mannequin_card.id, output["id"]
      assert_equal mannequin_card.note, output["note"]
      assert_equal mannequin_card.creator.id, output["creator"]["id"]
      assert_equal mannequin_card.creator.source_login, output["creator"]["login"]
      assert_equal mannequin_card.created_at, output["created_at"]
      assert_equal mannequin_card.updated_at, output["updated_at"]
    end
  end

  context "project_card_hash" do
    test "returns the expected card data" do
      card = create(:project_card, note: "do this thing")

      output = project_card(card)

      assert_equal card.id, output["id"]
      assert_equal card.note, output["note"]
      assert_equal card.creator.id, output["creator"]["id"]
      assert_equal card.creator.login, output["creator"]["login"]
      assert_equal card.created_at, output["created_at"]
      assert_equal card.updated_at, output["updated_at"]
    end

    test "returns a content_url that points to the card's content" do
      card = create(:project_card)
      repo = card.project.owner

      output = project_card(card)

      assert_equal "#{GitHub.api_url}/repos/#{repo.name_with_owner}/issues/#{card.content.number}", output["content_url"]
    end

    test "returns no content_url if the card has no content" do
      card = create(:note_project_card)

      output = project_card(card)

      assert_nil card.content
      refute output.key?(:content_url)
    end

    test "returns no content_url if the card's content is in a deleted repository" do
      repo = create(:repository)
      issue = create(:issue, repository: repo)
      card = create(:project_card, content: issue)
      repo.destroy
      card.reload

      output = project_card(card)

      refute output.key?(:content_url)
    end

    test "returns no content_url if the card is redacted" do
      card = create(:project_card)
      redacted_card = ProjectCardRedactor::RedactedCard.new(card, ProjectCardRedactor::RedactedCard::INSUFFICIENT_PERMISSION)

      output = project_card(redacted_card)

      refute output.key?(:content_url)
    end

    test "returns a URL" do
      card = create(:project_card)

      output = project_card(card)

      assert_equal "#{GitHub.api_url}/projects/columns/cards/#{card.id}", output["url"]
    end

    test "returns a column URL" do
      card = create(:project_card)

      output = project_card(card)

      assert_equal "#{GitHub.api_url}/projects/columns/#{card.column.id}", output["column_url"]
    end

    test "returns a project URL" do
      card = create(:project_card)

      output = project_card(card)

      assert_equal "#{GitHub.api_url}/projects/#{card.project_id}", output["project_url"]
    end

    test "works for a card on an organization-owned project" do
      project = create(:org_project)
      project.owner.add_member(@viewer)

      column = create(:project_column, project: project)
      card = create(:note_project_card, column: column)

      output = project_card(card)

      assert_equal card.id, output["id"]
    end
  end

  context "#graphql_team_project_hash" do
    test "payload is valid" do
      org = create(:organization)
      org.add_member(@viewer)

      project = create(:project, owner: org)
      team = create(:team, organization: org)

      team.add_project(project, :admin)
      team.add_member(@viewer)

      result = Api::App::PlatformClient.query(TeamProjectsQuery, context: { viewer: @viewer }, variables: { id: team.global_relay_id, limit: 10 })
      team_project_edge = result.data.team.projects.edges.first
      output = graphql_team_project(team_project_edge)
      assert output.key?("owner_url")
      assert output.key?("url")
      assert output.key?("html_url")
      assert output.key?("columns_url")
    end
  end
end
