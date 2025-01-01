# typed: true
# frozen_string_literal: true

class Api::Projects < Api::App
  include ReceiveSchemaWithOpenApi
  MAX_PER_PAGE = 100

  RepositoryIndexQuery = PlatformClient.parse <<-'GRAPHQL'
    query($repositoryId: ID!, $limit: Int!, $states: [ProjectState!], $numericPage: Int) {
      node(id: $repositoryId) {
        ... on Repository {
          name
          projects(states: $states, first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              node {
                ...Api::Serializer::ProjectsDependency::ProjectFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  get "/repositories/:repository_id/projects", operation_id: "projects/list-for-repo" do
    deprecate
    deliver_deprecation

    repo = find_repo!
    set_accepted_scopes_for_read(repo)

    control_access :list_projects,
      owner: repo,
      organization: repo.organization,
      resource: repo,
      forbid: repo.public?,
      challenge: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(repo)

    states = project_states_from(params[:state])
    variables = {
      "repositoryId" => repo.global_relay_id,
      "states" => states,
      "limit" => per_page,
      "numericPage" => pagination[:page],
    }

    results = platform_execute(RepositoryIndexQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    projects = results.data.node.projects

    paginator.collection_size = projects.total_count
    deliver :graphql_project_hash, projects.edges.map(&:node)
  end

  OrganizationIndexQuery = PlatformClient.parse <<-'GRAPHQL'
    query($organizationId: ID!, $limit: Int!, $states: [ProjectState!]!, $includePrivate: Boolean!, $numericPage: Int) {
      node(id: $organizationId) {
        ... on Organization {
          login
          projects(states: $states, includePrivate: $includePrivate, first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              node {
                ...Api::Serializer::ProjectsDependency::ProjectFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  get "/organizations/:organization_id/projects", operation_id: "projects/list-for-org" do
    deprecate
    deliver_deprecation

    org = find_org!
    set_accepted_scopes_for_read(org)

    control_access :apps_audited,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_projects_enabled_for_owner!(org)

    states = project_states_from(params[:state])
    include_private = access_allowed?(:list_projects,
      resource: org,
      owner: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
    )
    variables = {
      "organizationId" => org.global_relay_id,
      "states" => states,
      "limit" => per_page,
      "includePrivate" => include_private,
      "numericPage" => pagination[:page],
    }

    results = platform_execute(OrganizationIndexQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    projects = results.data.node.projects

    paginator.collection_size = projects.total_count
    deliver :graphql_project_hash, projects.edges.map(&:node)
  end

  UserIndexQuery = PlatformClient.parse <<-'GRAPHQL'
    query($userId: ID!, $limit: Int!, $states: [ProjectState!]!, $includePrivate: Boolean!, $numericPage: Int) {
      node(id: $userId) {
        ... on User {
          login
          projects(states: $states, includePrivate: $includePrivate, first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              node {
                ...Api::Serializer::ProjectsDependency::ProjectFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  get "/user/:user_id/projects", operation_id: "projects/list-for-user" do
    deprecate
    deliver_deprecation

    user = find_user!
    set_accepted_scopes_for_read(user)

    control_access :apps_audited,
      resource: user,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    states = project_states_from(params[:state])
    include_private = access_allowed?(:list_projects,
      resource: user,
      owner: user,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
    )

    ensure_user_is_not_organization(user)

    variables = {
      "userId" => user.global_relay_id,
      "states" => states,
      "limit" => per_page,
      "includePrivate" => include_private,
      "numericPage" => pagination[:page],
    }

    results = platform_execute(UserIndexQuery, variables: variables)

    if has_graphql_system_errors?(results)
      deprecated_deliver_graphql_error! errors: results.errors, resource: "Project"
    elsif has_graphql_mutation_errors?(results)
      deliver_graphql_mutation_errors! results, input_variables: variables, resource: "Project"
    end

    projects = results.data.node.projects

    paginator.collection_size = projects.total_count
    deliver :graphql_project_hash, projects.edges.map(&:node)
  end

  ShowProjectQuery = PlatformClient.parse <<-'GRAPHQL'
    query($projectId: ID!) {
      project: node(id: $projectId) {
        ...Api::Serializer::ProjectsDependency::ProjectFragment
      }
    }
  GRAPHQL

  get "/projects/:project_id", operation_id: "projects/get" do
    deprecate
    deliver_deprecation

    project = find_project!(param_name: :project_id)
    set_accepted_scopes_for_read(project.owner)

    control_access :show_project,
      resource:                   project,
      organization:               project.organization,
      forbid:                     true,
      challenge:                  true,
      allow_integrations:         true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(project.owner)

    results = platform_execute(ShowProjectQuery,
      variables: { "projectId" => project.global_relay_id },
    )

    deliver :graphql_project_hash, results.data.project
  end

  ProjectCardsQuery = PlatformClient.parse <<-'GRAPHQL'
    query($projectId: ID!, $includePending: Boolean!, $includeTriaged: Boolean!, $limit: Int!, $numericPage: Int) {
      project: node(id: $projectId) {
        ... on Project {
          databaseId
          cards(includePending: $includePending, includeTriaged: $includeTriaged, first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              node {
                ...Api::Serializer::ProjectsDependency::ProjectColumnCardFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  CreateRepositoryProjectQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($repositoryId: ID!, $name: String!, $body: String) {
      createProject(input: { ownerId: $repositoryId, name: $name, body: $body })  {
        project {
          ...Api::Serializer::ProjectsDependency::ProjectFragment
        }
      }
    }
  GRAPHQL

  post "/repositories/:repository_id/projects", operation_id: "projects/create-for-repo" do
    deprecate
    deliver_deprecation

    repo = find_repo!
    set_accepted_scopes_for_write(repo)

    control_access :create_project,
      owner: repo,
      organization: repo.organization,
      forbid: repo.public?,
      resource: repo,
      challenge: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(repo)

    ensure_projects_classic_creation_enabled_for_owner!(repo)

    authorize_content(:create, owner: repo)

    data = receive_with_schema("project", "create-for-repo-legacy")

    variables = {
      "repositoryId"     => repo.global_relay_id,
      "name"             => data["name"],
      "body"             => data["body"],
    }

    results = platform_execute(CreateRepositoryProjectQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver :graphql_project_hash, results.data.create_project.project, status: 201
  end

  CreateOrganizationProjectQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($organizationId: ID!, $name: String!, $body: String) {
      createProject(input: { ownerId: $organizationId, name: $name, body: $body })  {
        project {
          ...Api::Serializer::ProjectsDependency::ProjectFragment
        }
      }
    }
  GRAPHQL

  post "/organizations/:organization_id/projects", operation_id: "projects/create-for-org" do
    deprecate
    deliver_deprecation

    org = find_org!
    set_accepted_scopes_for_write(org)

    control_access :create_project,
      owner: org,
      organization: org,
      resource: org,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(org)
    ensure_projects_classic_creation_enabled_for_owner!(org)
    authorize_content(:create, owner: org)

    data = receive_with_schema("project", "create-for-org-legacy")

    variables = {
      "organizationId"   => org.global_relay_id,
      "name"             => data["name"],
      "body"             => data["body"],
    }

    results = platform_execute(CreateOrganizationProjectQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver :graphql_project_hash, results.data.create_project.project, status: 201
  end

  CreateUserProjectQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($userId: ID!, $name: String!, $body: String) {
      createProject(input: { ownerId: $userId, name: $name, body: $body })  {
        project {
          ...Api::Serializer::ProjectsDependency::ProjectFragment
        }
      }
    }
  GRAPHQL

  post "/user/projects", operation_id: "projects/create-for-authenticated-user" do
    deprecate
    deliver_deprecation

    set_accepted_scopes_for_write(current_user)

    control_access :create_project,
      owner: current_user,
      resource: current_user,
      forbid: true,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    authorize_content(:create, owner: current_user)

    ensure_projects_classic_creation_enabled_for_owner!(current_user)
    ensure_user_is_not_organization(current_user)

    data = receive_with_schema("project", "create-for-user")

    variables = {
      "userId" => current_user.global_relay_id,
      "name" => data["name"],
      "body" => data["body"],
    }

    results = platform_execute(CreateUserProjectQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver :graphql_project_hash, results.data.create_project.project, status: 201
  end

  UpdateProjectMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectId: ID!, $name: String, $body: String, $state: ProjectState, $organizationPermission: ProjectPermission, $public: Boolean) {
      updateProject(input: { projectId: $projectId, name: $name, body: $body, state: $state, organizationPermission: $organizationPermission, public: $public })  {
        project {
          ...Api::Serializer::ProjectsDependency::ProjectFragment
        }
      }
    }
  GRAPHQL

  patch "/projects/:project_id", operation_id: "projects/update" do
    deprecate
    deliver_deprecation

    project = find_project!(param_name: :project_id)
    set_accepted_scopes_for_write(project.owner)

    control_access :update_project,
      resource: project,
      organization: project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(project.owner)
    authorize_content(:update, project: project)

    data = receive_with_schema("project", "update-legacy")

    variables = { "projectId" => project.global_relay_id }
    variables["name"] = data["name"] if data.key?("name")
    variables["body"] = data["body"] if data.key?("body")
    variables["state"] = data["state"].upcase if data.key?("state")
    variables["organizationPermission"] = data["organization_permission"].upcase if data.key?("organization_permission")
    variables["public"] = !parse_bool(data["private"]) if data.key?("private")

    results = platform_execute(UpdateProjectMutation, variables: variables)

    if graphql_error?(results)
      status = forbidden_graphql_error?(results) ? 403 : 422
      deliver_error! status, errors: results.errors.all.values.flatten
    end

    deliver :graphql_project_hash, results.data.update_project.project
  end

  DeleteProjectMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectId: ID!) {
      deleteProject(input: { projectId: $projectId }) {
        clientMutationId
      }
    }
  GRAPHQL

  delete "/projects/:project_id", operation_id: "projects/delete" do
    deprecate
    deliver_deprecation

    # Introducing strict validation of the project.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("project", "delete", skip_validation: true)

    project = find_project!(param_name: :project_id)
    set_accepted_scopes_for_write(project.owner)

    control_access :delete_project,
      resource: project,
      organization: project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(project.owner)
    authorize_content(:destroy, project: project)

    variables = { "projectId" => project.global_relay_id }
    results = platform_execute(DeleteProjectMutation, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver_empty status: 204
  end

  ShowProjectColumnsQuery = PlatformClient.parse <<-'GRAPHQL'
    query($projectId: ID!, $limit: Int!, $numericPage: Int) {
      node(id: $projectId) {
        ... on Project {
          columns(first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              node {
                ...Api::Serializer::ProjectsDependency::ProjectColumnFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  get "/projects/:project_id/columns", operation_id: "projects/list-columns" do
    deprecate
    deliver_deprecation

    project = find_project!(param_name: :project_id)
    set_accepted_scopes_for_read(project.owner)

    control_access :show_project,
      resource:                   project,
      organization:               project.organization,
      forbid:                     true,
      challenge:                  true,
      allow_integrations:         true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(project.owner)

    variables = {
      "projectId"   => project.global_relay_id,
      "limit"       => per_page,
      "numericPage" => pagination[:page],
    }

    results = platform_execute(ShowProjectColumnsQuery, variables: variables)
    columns = results.data.node.columns

    paginator.collection_size = columns.total_count
    deliver :graphql_project_column_hash, columns.edges.map(&:node)
  end

  CreateProjectColumnMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectId: ID!, $columnName: String!) {
      addProjectColumn(input: { projectId: $projectId, name: $columnName }) {
        columnEdge {
          column: node {
            ...Api::Serializer::ProjectsDependency::ProjectColumnFragment
          }
        }
      }
    }
  GRAPHQL

  post "/projects/:project_id/columns", operation_id: "projects/create-column" do
    deprecate
    deliver_deprecation

    project = find_project!(param_name: :project_id)
    set_accepted_scopes_for_write(project.owner)

    control_access :update_project,
      resource: project,
      organization: project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(project.owner)
    authorize_content(:create, project: project)

    data = receive_with_schema("project-column", "create-legacy")

    column_name = data.fetch("name")

    variables = { "projectId" => project.global_relay_id, "columnName" => column_name }
    results = platform_execute(CreateProjectColumnMutation, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver :graphql_project_column_hash, results.data.add_project_column.column_edge.column, status: 201
  end

  ShowProjectColumnQuery = PlatformClient.parse <<-'GRAPHQL'
    query($projectColumnId: ID!) {
      column: node(id: $projectColumnId) {
        ...Api::Serializer::ProjectsDependency::ProjectColumnFragment
      }
    }
  GRAPHQL

  get "/projects/columns/:column_id", operation_id: "projects/get-column" do
    deprecate
    deliver_deprecation

    column = find_column!(param_name: :column_id)

    set_accepted_scopes_for_read(column.project.owner)

    control_access :show_project,
      resource:                   column.project,
      organization:               column.project.organization,
      forbid:                     true,
      challenge:                  true,
      allow_integrations:         true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(column.project.owner)

    variables = { "projectColumnId" => column.global_relay_id }

    results = platform_execute(ShowProjectColumnQuery, variables: variables)

    deliver :graphql_project_column_hash, results.data.column
  end

  UpdateProjectColumnMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectColumnId: ID!, $columnName: String!) {
      updateProjectColumn(input: { projectColumnId: $projectColumnId, name: $columnName }) {
        column: projectColumn {
          ...Api::Serializer::ProjectsDependency::ProjectColumnFragment
        }
      }
    }
  GRAPHQL

  patch "/projects/columns/:column_id", operation_id: "projects/update-column" do
    deprecate
    deliver_deprecation

    column = find_column!(param_name: :column_id)

    set_accepted_scopes_for_write(column.project.owner)

    control_access :update_project,
      resource: column.project,
      organization: column.project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(column.project.owner)
    authorize_content(:update, project: column.project)

    data = receive_with_schema("project-column", "update-legacy")
    column_name = data.fetch("name")

    variables = { "projectColumnId" => column.global_relay_id, "columnName" => column_name }

    results = platform_execute(UpdateProjectColumnMutation, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver :graphql_project_column_hash, results.data.update_project_column.column
  end

  DeleteProjectColumnMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($columnId: ID!) {
      deleteProjectColumn(input: { columnId: $columnId }) {
        clientMutationId
      }
    }
  GRAPHQL

  delete "/projects/columns/:column_id", operation_id: "projects/delete-column" do
    deprecate
    deliver_deprecation

    # Introducing strict validation of the project-column.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("project-column", "delete", skip_validation: true)

    column = find_column!(param_name: :column_id)

    set_accepted_scopes_for_write(column.project.owner)

    control_access :update_project,
      resource: column.project,
      organization: column.project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(column.project.owner)
    authorize_content(:destroy, project: column.project)

    variables = { "columnId" => column.global_relay_id }

    results = platform_execute(DeleteProjectColumnMutation, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver_empty status: 204
  end

  MoveProjectColumnQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($columnId: ID!, $afterColumnId: ID) {
      moveProjectColumn(input: { columnId: $columnId, afterColumnId: $afterColumnId }) {
        clientMutationId
      }
    }
  GRAPHQL

  post "/projects/columns/:column_id/moves", operation_id: "projects/move-column" do
    deprecate
    deliver_deprecation

    column = find_column!(param_name: :column_id)

    set_accepted_scopes_for_write(column.project.owner)

    control_access :update_project,
      resource: column.project,
      organization: column.project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(column.project.owner)
    authorize_content(:update, project: column.project)

    data = receive_with_schema("project-column-move", "create-legacy")

    position, relative_column_id = data["position"].split(":")

    case position
    when "last"
      after_column_relay_id = column.project.columns.last.global_relay_id
      halt deliver_empty status: 201 if after_column_relay_id == column.global_relay_id
    when "first"
      after_column_relay_id = nil
    when "after"
      after_column_relay_id = Platform::Helpers::NodeIdentification.to_legacy_global_id("ProjectColumn", relative_column_id)
    else
      deliver_error!(422, message: "Invalid position parameter")
    end

    variables = {
      "columnId"         => column.global_relay_id,
      "afterColumnId"    => after_column_relay_id,
    }

    results = platform_execute(MoveProjectColumnQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver_empty status: 201
  end

  ProjectColumnCardsQuery = PlatformClient.parse <<-'GRAPHQL'
    query($columnId: ID!, $archivedStates: [ProjectCardArchivedState]!, $limit: Int!, $numericPage: Int) {
      node(id: $columnId) {
        ... on ProjectColumn {
          databaseId
          cards(archivedStates: $archivedStates, first: $limit, numericPage: $numericPage) {
            totalCount
            edges {
              node {
                ...Api::Serializer::ProjectsDependency::ProjectColumnCardFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  get "/projects/columns/:column_id/cards", operation_id: "projects/list-cards" do
    deprecate
    deliver_deprecation

    column = find_column!(param_name: :column_id)

    set_accepted_scopes_for_read(column.project.owner)

    control_access :show_project,
      resource: column.project,
      organization: column.project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(column.project.owner)

    archived_states = case params[:archived_state]
    when "all"
      %w[ARCHIVED NOT_ARCHIVED]
    when "archived"
      ["ARCHIVED"]
    else
      ["NOT_ARCHIVED"]
    end

    variables = {
      "columnId" => column.global_relay_id,
      "archivedStates" => archived_states,
      "limit" => per_page,
      "numericPage" => pagination[:page],
    }

    results = platform_execute(ProjectColumnCardsQuery, variables: variables)
    cards = results.data.node.cards

    paginator.collection_size = cards.total_count
    deliver :graphql_project_card_hash, cards.edges.map(&:node)
  end

  AddProjectCardMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectColumnId: ID!, $contentId: ID, $note: String) {
      addProjectCard(input: { projectColumnId: $projectColumnId, contentId: $contentId, note: $note }) {
        cardEdge {
          card: node {
            ...Api::Serializer::ProjectsDependency::ProjectColumnCardFragment
          }
        }
      }
    }
  GRAPHQL

  post "/projects/columns/:column_id/cards", operation_id: "projects/create-card" do
    deprecate
    deliver_deprecation

    column = find_column!(param_name: :column_id)

    set_accepted_scopes_for_write(column.project.owner)

    control_access :update_project,
      resource: column.project,
      organization: column.project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(column.project.owner)
    authorize_content(:update, project: column.project)

    data = receive_with_schema("project-card", "create-in-column-legacy")

    card_content_type = data["content_type"]
    card_content_id   = data["content_id"]

    if card_content_id.present?
      if card_content_type.present?
        content_relay_id = Platform::Helpers::NodeIdentification.to_legacy_global_id(card_content_type, card_content_id)
      else
        deliver_error! 422, errors: ["You must provide a content_type with a content_id."],
          documentation_url: @documentation_url
      end
    end

    variables = {
      "projectColumnId" => column.global_relay_id,
      "contentId" => content_relay_id,
      "note" => data["note"],
    }

    results = platform_execute(AddProjectCardMutation, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error(
        errors: results.errors.all,
        resource: "ProjectCard",
        documentation_url: "#{GitHub.developer_help_url}/v3/projects/cards/#create-a-project-card",
      )
    else
      deliver :graphql_project_card_hash, results.data.add_project_card.card_edge.card, status: 201
    end
  end

  ProjectColumnCardQuery = PlatformClient.parse <<-'GRAPHQL'
    query($cardId: ID!) {
      card: node(id: $cardId) {
        ...Api::Serializer::ProjectsDependency::ProjectColumnCardFragment
      }
    }
  GRAPHQL

  get "/projects/columns/cards/:card_id", operation_id: "projects/get-card" do
    deprecate
    deliver_deprecation

    card = find_card!(param_name: :card_id)

    set_accepted_scopes_for_read(card.project.owner)

    control_access :show_project,
      resource:                   card.project,
      organization:               card.project.organization,
      forbid:                     true,
      challenge:                  true,
      allow_integrations:         true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(card.project.owner)

    variables = { "cardId" => card.global_relay_id }

    deliver_error! 404 if card.pending?

    results = platform_execute(ProjectColumnCardQuery, variables: variables)
    deliver :graphql_project_card_hash, results.data.card
  end

  UpdateProjectCardMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($projectCardId: ID!, $isArchived: Boolean, $note: String,) {
      updateProjectCard(input: { projectCardId: $projectCardId, isArchived: $isArchived, note: $note }) {
        card: projectCard {
          ...Api::Serializer::ProjectsDependency::ProjectColumnCardFragment
        }
      }
    }
  GRAPHQL

  patch "/projects/columns/cards/:card_id", operation_id: "projects/update-card" do
    deprecate
    deliver_deprecation

    card = find_card!(param_name: :card_id)

    if card.pending?
      deliver_error! 404
    end

    set_accepted_scopes_for_write(card.project.owner)

    control_access :update_project,
      resource: card.project,
      organization: card.project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(card.project.owner)
    authorize_content(:update, project: card.project)

    data = receive_with_schema("project-card", "update-legacy")

    variables = { "projectCardId" => card.global_relay_id }
    variables["note"] = data["note"] if data.key?("note")
    variables["isArchived"] = parse_bool(data["archived"]) if data.key?("archived")

    results = platform_execute(UpdateProjectCardMutation, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    deliver :graphql_project_card_hash, results.data.update_project_card.card
  end

  DeleteProjectCardMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($cardId: ID!) {
      deleteProjectCard(input: {cardId: $cardId}) {
        clientMutationId
      }
    }
  GRAPHQL

  delete "/projects/columns/cards/:card_id", operation_id: "projects/delete-card" do
    deprecate
    deliver_deprecation

    # Introducing strict validation of the project-card.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("project-card", "delete", skip_validation: true)

    card = find_card!(param_name: :card_id)

    deliver_error! 404 if card.pending?

    set_accepted_scopes_for_write(card.project.owner)

    control_access :delete_project,
      resource: card.project,
      organization: card.project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(card.project.owner)
    authorize_content(:update, project: card.project)

    variables = { "cardId" => card.global_relay_id }

    results = platform_execute(DeleteProjectCardMutation, variables: variables)

    if graphql_error?(results)
      status = forbidden_graphql_error?(results) ? 403 : 422
      deliver_error! status, errors: results.errors.all.values.flatten
    end

    deliver_empty status: 204
  end

  MoveProjectCardMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($cardId: ID!, $columnId: ID!, $afterCardId: ID) {
      moveProjectCard(input: { cardId: $cardId, columnId: $columnId, afterCardId: $afterCardId }) {
        clientMutationId
      }
    }
  GRAPHQL

  post "/projects/columns/cards/:card_id/moves", operation_id: "projects/move-card" do
    deprecate
    deliver_deprecation

    card = find_card!(param_name: :card_id)

    set_accepted_scopes_for_write(card.project.owner)

    control_access :update_project,
      resource: card.project,
      organization: card.project.organization,
      forbid: true,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_projects_enabled_for_owner!(card.project.owner)
    authorize_content(:update, project: card.project)

    data = receive_with_schema("project-card-move", "create-legacy")

    if data["column_id"]
      column_id = data["column_id"]
      column_relay_id = Platform::Helpers::NodeIdentification.to_legacy_global_id("ProjectColumn", column_id)
    else
      column_id = card.column.id
      column_relay_id = card.column.global_relay_id
    end

    position, relative_card_id = data["position"].split(":")

    case position
    when "bottom"
      begin
        destination_column = card.project.columns.find(column_id)
      rescue ActiveRecord::RecordNotFound
        deliver_error!(422, message: "Invalid column ID")
      end

      last_card_in_column = destination_column.ordered_cards_for(current_user).last
      if last_card_in_column == card
        halt deliver_empty status: 201
      else
        after_card_relay_id = last_card_in_column.global_relay_id if last_card_in_column
      end
    when "top"
      after_card_relay_id = nil
    when "after"
      after_card_relay_id = Platform::Helpers::NodeIdentification.to_legacy_global_id("ProjectCard", relative_card_id)
    else
      deliver_error!(422, message: "Invalid position parameter")
    end

    variables = {
      "cardId"           => card.global_relay_id,
      "columnId"         => column_relay_id,
      "afterCardId"      => after_card_relay_id,
    }

    results = platform_execute(MoveProjectCardMutation, variables: variables)

    if graphql_error?(results)
      error_options = {
        errors: results.errors.all,
        resource: "ProjectCard",
        documentation_url: @documentation_url,
      }
      error_options[:status] = 403 if forbidden_graphql_error?(results)
      deprecated_deliver_graphql_error(error_options)
    else
      deliver_empty status: 201
    end
  end

  private

  def find_project!(param_name: :id)
    return @find_project if defined?(@find_project)

    @find_project = Project.find_by(id: int_id_param!(key: param_name))
    set_oap_enforcement_target(@find_project)

    record_or_404(@find_project)
  end

  def find_column!(param_name: :id)
    return @find_column if defined?(@find_column)

    @find_column = ProjectColumn.find_by(id: int_id_param!(key: param_name))
    set_oap_enforcement_target(@find_column&.project)

    record_or_404(@find_column)
  end

  def find_card!(param_name: :id)
    return @find_card if defined?(@find_card)

    @find_card = ProjectCard.find_by(id: int_id_param!(key: param_name))
    set_oap_enforcement_target(@find_card&.project)

    record_or_404(@find_card)
  end

  def graphql_error?(results)
    results.errors.all.any?
  end

  def forbidden_graphql_error?(results)
    results.errors.all.details["data"]&.any? { |d| d["type"] == "FORBIDDEN" }
  end

  def ensure_user_is_not_organization(user)
    if user.organization?
      message = "ID #{params[:user_id]} is an Organization, not a User. Change your request to use Organization endpoints."
      deliver_error!(422,
        message: message,
        documentation_url: "#{GitHub.developer_help_url}/v3/projects/")
    end
  end

  # Set current repo/org for OAP enforcement
  # Not required for user projects
  def set_oap_enforcement_target(project)
    case project&.owner_type
    when "Repository"
      @current_repo ||= project.owner
    when "Organization"
      @current_org ||= project.owner
    end
  end

  def set_accepted_scopes_for_read(owner)
    @accepted_scopes = ["repo"]
    if owner.is_a?(Repository)
      if owner.public?
        set_forbidden_message "You need at least public_repo scope to view public repository projects via OAuth"
        @accepted_scopes << "public_repo"
      end
    elsif owner.instance_of?(Organization)
      # TODO: remove `repo` scope in favor or `read:org`
      # https://github.com/github/github/issues/108838
      @accepted_scopes << "read:org"
    end
  end

  def set_accepted_scopes_for_write(owner)
    @accepted_scopes = ["repo"]
    if owner.is_a?(Repository)
      if owner.public?
        set_forbidden_message "You need at least public_repo scope to view public repository projects via OAuth"
        @accepted_scopes << "public_repo"
      end
    elsif owner.instance_of?(Organization)
      # TODO: remove `repo` scope in favor or `read:org`
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

  def ensure_projects_classic_creation_enabled_for_owner!(source)
    return if GitHub.projects_classic_creation_enabled?

    # Switch to allow users (such as staff) to create classic projects
    return if current_user.feature_enabled?(:memex_bypass_projects_classic_deprecation_rules)

    deliver_error!(
      410,
      message: "Projects are disabled for this #{source.class.name.downcase}",
      documentation_url: "/v3/projects",
    )
  end

  def project_states_from(state)
    case state
    when "all"
      # Expand "all" out into every state
      Platform::Enums::ProjectState.graphql_values
    when nil
      # Default to open
      ["OPEN"]
    else
      [state.upcase]
    end
  end

  def authorize_content(operation = :create, data = {})
    authorization = ContentAuthorizer.authorize(current_user, :project, operation, data)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end

  def deprecate
    deprecated(
      deprecation_date: ProjectsClassicSunset::REST_API_DEPRECATION_DATE,
      sunset_date: ProjectsClassicSunset::REST_API_SUNSET_DATE,
      info_url: ProjectsClassicSunset::REST_API_DEPRECATION_INFO_URL
    )
  end

  def deliver_deprecation
    deliver_error!(
      410,
      message: ProjectsClassicSunset::REST_API_SUNSET_MESSAGE,
      documentation_url: ProjectsClassicSunset::REST_API_SUNSET_DOCUMENTATION_URL,
      ) unless ProjectsClassicSunset.rest_api_enabled?(current_user)
  end
end
