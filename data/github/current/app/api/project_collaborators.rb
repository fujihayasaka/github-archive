# typed: true
# frozen_string_literal: true

class Api::ProjectCollaborators < Api::App
  include ReceiveSchemaWithOpenApi

  MAX_PER_PAGE = 30

  IndexQuery = PlatformClient.parse <<-'GRAPHQL'
    query($projectId: ID!, $affiliation: CollaboratorAffiliation, $limit: Int!, $numericPage: Int) {
      project: node(id: $projectId) {
        ... on Project {
          usersWithAccess(affiliation: $affiliation, first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              node {
                ...Api::Serializer::UserDependency::SimpleUserFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  get "/projects/:project_id/collaborators", operation_id: "projects-classic/list-collaborators" do
    deprecate
    deliver_deprecation!

    project = find_project!(param_name: :project_id)
    set_accepted_scopes_for_owner(project.owner)

    control_access :list_project_collaborators,
      resource: project,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(project.owner)

    variables = {
      "projectId" => project.global_relay_id,
      "limit" => per_page,
      "numericPage" => pagination[:page],
      "affiliation" => params[:affiliation]&.upcase,
    }

    results = platform_execute(IndexQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error! resource: "Project", status: 422, errors: results.errors.all
    end

    collaborators = results.data.project.users_with_access

    paginator.collection_size = collaborators.total_count
    deliver :graphql_simple_user_hash, collaborators.edges.map(&:node)
  end

  UserPermissionQuery = PlatformClient.parse <<-'GRAPHQL'
    query($projectId: ID!, $userId: ID!) {
      project: node(id: $projectId) {
        ... on Project {
          userPermission(userId: $userId)
        }
      }

      user: node(id: $userId) {
        ... on User {
          ...Api::Serializer::UserDependency::SimpleUserFragment
        }
      }
    }
  GRAPHQL

  get "/projects/:project_id/collaborators/:username/permission", operation_id: "projects-classic/get-permission-for-user" do
    deprecate
    deliver_deprecation!

    project = find_project!(param_name: :project_id)
    user = record_or_404(User.find_by_login(params[:username]))

    set_accepted_scopes_for_owner(project.owner)

    control_access :list_project_collaborators,
      resource: project,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(project.owner)

    variables = {
      "projectId" => project.global_relay_id,
      "userId" => user.global_relay_id,
    }

    results = platform_execute(UserPermissionQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error! resource: "Project", status: 422, errors: results.errors.all
    end

    deliver :graphql_user_project_permission_hash, results.data.project.user_permission, user: results.data.user
  end

  AddCollaboratorQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectId: ID!, $userId: ID!, $permission: ProjectPermission!) {
      addProjectCollaborator(input: { projectId: $projectId, userId: $userId, permission: $permission }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  UpdateCollaboratorQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectId: ID!, $userId: ID!, $permission: ProjectPermission!) {
      updateProjectCollaborator(input: { projectId: $projectId, userId: $userId, permission: $permission }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  put "/projects/:project_id/collaborators/:username", operation_id: "projects-classic/add-collaborator" do
    deprecate
    deliver_deprecation!

    project = find_project!(param_name: :project_id)
    user = record_or_404(User.find_by_login(params[:username]))

    set_accepted_scopes_for_owner(project.owner)

    control_access :add_project_collaborator,
      resource: project,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(project.owner)

    data = receive_with_schema("project-collaborator", "add")

    permission = data && data["permission"]
    variables = {
      "projectId" => project.global_relay_id,
      "userId" => user.global_relay_id,
      "permission" => (permission || "write").upcase,
    }

    query = if project.direct_collaborators.include?(user)
      UpdateCollaboratorQuery
    else
      AddCollaboratorQuery
    end

    results = platform_execute(query, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error! resource: "Project", status: 422, errors: results.errors.all
    end

    deliver_empty status: 204
  end

  RemoveCollaboratorQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectId: ID!, $userId: ID!) {
      removeProjectCollaborator(input: { projectId: $projectId, userId: $userId }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  delete "/projects/:project_id/collaborators/:username", operation_id: "projects-classic/remove-collaborator" do
    deprecate
    deliver_deprecation!

    receive_with_schema("project-collaborator", "delete")

    project = find_project!(param_name: :project_id)
    user = record_or_404(User.find_by_login(params[:username]))

    set_accepted_scopes_for_owner(project.owner)

    control_access :remove_project_collaborator,
      resource: project,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(project.owner)

    variables = {
      "projectId" => project.global_relay_id,
      "userId" => user.global_relay_id,
    }

    results = platform_execute(RemoveCollaboratorQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error! resource: "Project", status: 422, errors: results.errors.all
    end

    deliver_empty status: 204
  end

  private

  def find_project!(param_name: :id)
    return @find_project if defined?(@find_project)

    @find_project = Project.find_by(id: int_id_param!(key: param_name))

    # Set current repo/org for OAP enforcement.
    case @find_project&.owner_type
    when "Repository"
      @current_repo ||= T.must(@find_project).owner
    when "Organization"
      @current_org ||= T.must(@find_project).owner
    end

    record_or_404(@find_project)
  end

  def set_accepted_scopes_for_owner(owner)
    @accepted_scopes = ["repo"]
    @accepted_scopes = if owner.is_a?(Repository)
      if owner.public?
        set_forbidden_message "You need at least public_repo scope to view public repository projects via OAuth"
        @accepted_scopes << "public_repo"
      end
    elsif owner.instance_of?(Organization)
      # TODO: remove `repo` scope in favor or `write:org`
      # https://github.com/github/github/issues/108838
      @accepted_scopes << "write:org"
    end
  end

  def ensure_projects_enabled_for_owner!(owner)
    unless owner.projects_enabled?
      deliver_error!(
        410,
        message: "Projects are disabled for this #{owner.class.name.downcase}",
        documentation_url: "/v3/projects",
      )
    end
  end

  def deprecate
    deprecated(
      deprecation_date: ProjectsClassicSunset::REST_API_DEPRECATION_DATE,
      sunset_date: ProjectsClassicSunset::REST_API_SUNSET_DATE,
      info_url: ProjectsClassicSunset::REST_API_DEPRECATION_INFO_URL
    )
  end

  def deliver_deprecation!
    deliver_error!(
      410,
      message: ProjectsClassicSunset::REST_API_SUNSET_MESSAGE,
      documentation_url: ProjectsClassicSunset::REST_API_SUNSET_DOCUMENTATION_URL,
    ) unless ProjectsClassicSunset.rest_api_enabled?(current_user)
  end
end
