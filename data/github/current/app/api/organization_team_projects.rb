# typed: true
# frozen_string_literal: true

class Api::OrganizationTeamProjects < Api::App
  include ReceiveSchemaWithOpenApi

  TeamProjectsQuery = PlatformClient.parse <<-'GRAPHQL'
    query($id: ID!, $affiliation: TeamProjectType, $limit: Int!, $numericPage: Int) {
      node(id: $id) {
        ... on Team {
          projects(affiliation: $affiliation, first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              ...Api::Serializer::ProjectsDependency::TeamProjectEdgeFragment
            }
          }
        }
      }
    }
  GRAPHQL

  get "/organizations/:org_id/team/:team_id/projects", operation_id: "teams/list-projects-in-org" do
    deprecate
    deliver_deprecation!

    team = find_team!
    control_access :list_team_projects,
      resource: team,
      organization: team.organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variables = {
      id: team.global_relay_id,
      limit: per_page,
      numericPage: pagination[:page],
      affiliation: "ALL",
    }

    results = platform_execute(TeamProjectsQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error({
        errors: results.errors.all,
        resource: "Team",
        documentation_url: @documentation_url,
      })
    else
      projects = results.data.node.projects

      paginator.collection_size = projects.total_count
      deliver :graphql_team_project_hash, projects.edges, team: team
    end
  end

  ReviewTeamProjectQuery = PlatformClient.parse <<-'GRAPHQL'
    query($teamId: ID!, $projectId: ID!, $affiliation: TeamProjectType) {
      node(id: $teamId) {
        ... on Team {
          projects(id: $projectId, affiliation: $affiliation, first: 1) {
            edges {
              ...Api::Serializer::ProjectsDependency::TeamProjectEdgeFragment
            }
          }
        }
      }
    }
  GRAPHQL

  # review a project in a team
  get "/organizations/:org_id/team/:team_id/projects/:project_id", operation_id: "teams/check-permissions-for-project-in-org" do
    deprecate
    deliver_deprecation!

    team = find_team!
    project = find_project!

    control_access :list_team_projects,
      resource: team,
      organization: team.organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variables = {
      teamId: team.global_relay_id,
      projectId: project.global_relay_id,
      affiliation: "ALL",
    }

    results = platform_execute(ReviewTeamProjectQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error({
        errors: results.errors.all,
        resource: "Team",
        documentation_url: @documentation_url,
      })
    else
      deliver :graphql_team_project_hash, results.data.node.projects.edges.first, team: team
    end
  end

  AddTeamProjectQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectId: ID!, $teamId: ID!, $permission: ProjectPermission!) {
      addTeamProject(input: { projectId: $projectId, teamId: $teamId, permission: $permission }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  UpdateTeamProjectQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectId: ID!, $teamId: ID!, $permission: ProjectPermission!) {
      updateTeamProject(input: { projectId: $projectId, teamId: $teamId, permission: $permission }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  put "/organizations/:org_id/team/:team_id/projects/:project_id", operation_id: "teams/add-or-update-project-permissions-in-org" do
    deprecate
    deliver_deprecation!

    team = find_team!
    project = find_project!

    control_access :add_team_project,
      resource: team,
      organization: team.organization,
      project: project,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("team-project", "update")

    variables = {
      teamId: team.global_relay_id,
      projectId: project.global_relay_id,
      permission: (data["permission"] || "write").upcase,
    }

    query = if team.projects.include?(project)
      UpdateTeamProjectQuery
    else
      AddTeamProjectQuery
    end

    results = platform_execute(query, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error({
        errors: results.errors.all,
        resource: "Team",
        documentation_url: @documentation_url,
      })
    else
      deliver_empty status: 204
    end
  end

  RemoveTeamProjectQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectId: ID!, $teamId: ID!) {
      removeTeamProject(input: { projectId: $projectId, teamId: $teamId }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  delete "/organizations/:org_id/team/:team_id/projects/:project_id", operation_id: "teams/remove-project-in-org" do
    deprecate
    deliver_deprecation!

    receive_with_schema("team-project", "delete")

    team = find_team!
    project = find_project!

    control_access :remove_team_project,
      resource: team,
      organization: team.organization,
      project: project,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variables = {
      teamId: team.global_relay_id,
      projectId: project.global_relay_id,
    }

    results = platform_execute(RemoveTeamProjectQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error({
        errors: results.errors.all,
        resource: "Team",
        documentation_url: @documentation_url,
      })
    else
      deliver_empty status: 204
    end
  end

  private

  def find_project!
    return @find_project if defined?(@find_project)

    @find_project = Project.find_by(id: int_id_param!(key: :project_id))

    # Set current repo/org for OAP enforcement.
    case @find_project&.owner_type
    when "Repository"
      @current_repo ||= @find_project&.owner
    when "Organization"
      @current_org ||= @find_project&.owner
    end

    record_or_404(@find_project)
  end

  def deprecate
    deprecated(
      deprecation_date: ProjectsClassicSunset::REST_API_DEPRECATION_DATE,
      sunset_date: ProjectsClassicSunset::REST_API_SUNSET_DATE,
      info_url: ProjectsClassicSunset::REST_API_DEPRECATION_INFO_URL
    ) if GitHub::flipper[:projects_classic_rest_api_deprecation_notice].enabled?(current_user) # rubocop:disable GitHub/UseActorFeatureEnabled
  end

  def deliver_deprecation!
    deliver_error!(
      410,
      message: ProjectsClassicSunset::REST_API_SUNSET_MESSAGE,
      documentation_url: ProjectsClassicSunset::REST_API_SUNSET_DOCUMENTATION_URL,
    ) unless ProjectsClassicSunset.rest_api_enabled?(current_user)
  end
end
