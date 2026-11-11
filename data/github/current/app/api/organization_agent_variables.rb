# typed: true
# frozen_string_literal: true

require "github/kredz_client"

class Api::OrganizationAgentVariables < Api::App
  include Api::App::ActionsVariablesHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  def self.agent_secrets_app
    Apps::Privileged.integration(:agent_secrets)
  end

  get "/organizations/:organization_id/agents/variables", operation_id: "agents/list-org-variables" do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_variables?(org)

    control_access :read_agent_variables_org,
      resource: org,
      forbid: true,
      forbid_message: "Agent variables are not available for this organization",
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    @paginator = build_paginator(default_per_page: GitHub::KredzClient::Varz::DEFAULT_VARIABLES_PER_PAGE, max_per_page: GitHub::KredzClient::Varz::MAX_VARIABLES_PER_PAGE)

    result = rescue_from_variables_errors do
      Variables.list(
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
        page: pagination[:page],
        per_page: pagination[:per_page],
      )
    end

    validate_listing!(result)
    deliver_error! 404 unless result

    deliver :agent_org_variables_hash, { variables: result.variables, total_count: result.total_count, org: org }
  end

  get "/organizations/:organization_id/agents/variables/:name", operation_id: "agents/get-org-variable" do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_variables?(org)

    control_access :read_agent_variables_org,
      resource: org,
      forbid: true,
      forbid_message: "Agent variables are not available for this organization",
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_variables_errors do
      Variables.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :agent_org_variable_hash, { variable: result.variable, org: org }
  end

  post "/organizations/:organization_id/agents/variables", operation_id: "agents/create-org-variable", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_variables?(org)

    control_access :write_agent_variables_org,
      resource: org,
      forbid: true,
      forbid_message: "Agent variables are not available for this organization",
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi
    name = data["name"]
    value = data["value"]
    visibility = GitHub::KredzClient::Varz::FROM_VISIBILITY_MAP[data["visibility"]]
    selected_repository_ids = data["selected_repository_ids"]

    validation = Varz.validate_new_org_variable(name, value, visibility)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error
    end

    encoded_value = Base64.strict_encode64(value)

    org_repository_ids = org.repositories.where(id: selected_repository_ids).map(&:global_relay_id)

    result = rescue_from_variables_errors do
      Variables.store(
        name: name,
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
        value: encoded_value,
        visibility: visibility,
        selected_repositories: org_repository_ids,
      )
    end

    validate_result!(result)
    validate_storage!(result)

    deliver_empty(status: 201)
  end

  patch "/organizations/:organization_id/agents/variables/:name", operation_id: "agents/update-org-variable", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_variables?(org)

    control_access :write_agent_variables_org,
      resource: org,
      forbid: true,
      forbid_message: "Agent variables are not available for this organization",
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi
    updated_name = data["name"]
    value = data["value"]
    visibility = GitHub::KredzClient::Varz::FROM_VISIBILITY_MAP[data["visibility"]]
    selected_repository_ids = data["selected_repository_ids"]

    validation = Varz.validate_org_update_request(updated_name, value, visibility, current_user, selected_repository_ids)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error
    end

    org_repository_ids = []
    unless selected_repository_ids.nil?
      org_repository_ids = org.repositories.where(id: selected_repository_ids).map(&:global_relay_id)
    end

    if visibility.nil? || (visibility == GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS && selected_repository_ids.nil?)
      response = rescue_from_variables_errors do
        Variables.fetch(
          name: params[:name],
          app: self.class.agent_secrets_app,
          owner: org,
          actor: current_user,
        )
      end

      variable = response.variable
      visibility = variable.visibility if visibility.nil?
      org_repository_ids = variable.selected_repositories.map(&:global_id) if selected_repository_ids.nil?
    end

    encoded_value = Base64.strict_encode64(value || "")

    result = rescue_from_variables_errors do
      Variables.update(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
        value: encoded_value,
        visibility: visibility,
        selected_repositories: org_repository_ids,
        updated_name: updated_name || "",
      )
    end

    validate_result!(result)
    validate_update!(result)

    deliver_empty(status: 204)
  end

  delete "/organizations/:organization_id/agents/variables/:name", operation_id: "agents/delete-org-variable", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_variables?(org)

    control_access :write_agent_variables_org,
      resource: org,
      forbid: true,
      forbid_message: "Agent variables are not available for this organization",
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    result = rescue_from_variables_errors do
      Variables.delete(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: (result.success ? 204 : 404)
  end

  get "/organizations/:organization_id/agents/variables/:name/repositories", operation_id: "agents/list-selected-repos-for-org-variable" do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_variables?(org)

    control_access :read_agent_variables_org,
      resource: org,
      forbid: true,
      forbid_message: "Agent variables are not available for this organization",
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_variables_errors do
      Variables.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    variable = result.variable
    unless variable.visibility == GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS
      deliver_error! 409, errors: "You can only list selected repositories for a variable when the visibility is set to 'selected'"
    end

    total_count = variable.selected_repositories_count
    repository_ids = map_selected_repo_global_ids(variable)
    repositories = org.repositories.where(id: repository_ids)
    repositories = paginate_rel(repositories.sorted_by(:full_name, "asc"))

    deliver :agent_variable_repositories_hash, { repositories: repositories, total_count: total_count }
  end

  put "/organizations/:organization_id/agents/variables/:name/repositories", operation_id: "agents/set-selected-repos-for-org-variable", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_variables?(org)

    control_access :write_agent_variables_org,
      resource: org,
      forbid: true,
      forbid_message: "Agent variables are not available for this organization",
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_variables_errors do
      Variables.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    variable = result.variable
    unless variable.visibility == GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS
      deliver_error! 409, errors: "You cannot set selected repositories for a variable when the visibility is not set to 'selected'"
    end

    data = receive_with_openapi
    selected_repository_ids = data["selected_repository_ids"]

    org_repository_ids = org.repositories.where(id: selected_repository_ids).map(&:global_relay_id)

    result = rescue_from_variables_errors do
      Variables.update(
        name: variable.name,
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
        visibility: variable.visibility,
        selected_repositories: org_repository_ids,
        updated_name: "",
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end

  put "/organizations/:organization_id/agents/variables/:name/repositories/:repository_id", operation_id: "agents/add-selected-repo-to-org-variable", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_variables?(org)

    control_access :write_agent_variables_org,
      resource: org,
      forbid: true,
      forbid_message: "Agent variables are not available for this organization",
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_variables_errors do
      Variables.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    variable = result.variable
    unless variable.visibility == GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS
      deliver_error! 409, errors: "You cannot add a selected repository for a variable when the visibility is not set to 'selected'"
    end

    repo = find_repo!
    deliver_error! 422 unless repo.organization_id == org.id

    selected_repository_node_ids = variable.selected_repositories.map(&:global_id).to_set
    selected_repositories_ids = selected_repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = org.repositories.where(id: selected_repositories_ids)

    selected_repository_global_ids = selected_repositories.map(&:global_relay_id).to_set
    selected_repository_global_ids << repo.global_relay_id

    result = rescue_from_variables_errors do
      Variables.update(
        name: variable.name,
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
        visibility: variable.visibility,
        selected_repositories: selected_repository_global_ids.to_a,
        updated_name: "",
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end

  delete "/organizations/:organization_id/agents/variables/:name/repositories/:repository_id", operation_id: "agents/remove-selected-repo-from-org-variable", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_variables?(org)

    control_access :write_agent_variables_org,
      resource: org,
      forbid: true,
      forbid_message: "Agent variables are not available for this organization",
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_variables_errors do
      Variables.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    variable = result.variable
    unless variable.visibility == GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS
      deliver_error! 409, errors: "You cannot remove a selected repository for a variable when the visibility is not set to 'selected'"
    end

    repo_id = params[:repository_id]
    selected_repositories_ids = map_selected_repo_global_ids(variable).to_set
    deliver_error! 404 unless selected_repositories_ids.include?(repo_id)

    selected_repositories_ids.delete(repo_id)

    org_repository_ids = org.repositories.where(id: selected_repositories_ids).map(&:global_relay_id)

    result = rescue_from_variables_errors do
      Variables.update(
        name: variable.name,
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
        visibility: variable.visibility,
        selected_repositories: org_repository_ids,
        updated_name: "",
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end

  private

  def can_use_org_variables?(organization)
    Billing::ActionsPermission.new(organization).status[:error][:reason] != "PLAN_INELIGIBLE"
  end

  def agents_enabled?(org)
    Secrets::AppsHelper.agents_enabled?(repo: nil, owner: org)
  end
end
