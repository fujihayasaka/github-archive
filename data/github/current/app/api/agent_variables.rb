# typed: true
# frozen_string_literal: true

require "github/kredz_client"

class Api::AgentVariables < Api::App
  include Api::App::ActionsVariablesHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  def self.agent_secrets_app
    Apps::Privileged.integration(:agent_secrets)
  end

  get "/repositories/:repository_id/agents/variables", operation_id: "agents/list-repo-variables" do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :read_agent_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent variables are not available for public repositories",
      allow_integrations: true,
      enforce_oauth_app_policy: true, allow_user_via_granular_actor: true

    @paginator = build_paginator(default_per_page: GitHub::KredzClient::Varz::DEFAULT_VARIABLES_PER_PAGE, max_per_page: GitHub::KredzClient::Varz::MAX_VARIABLES_PER_PAGE)

    result = rescue_from_variables_errors do
      Variables.list(
        app: self.class.agent_secrets_app,
        owner: repo,
        actor: current_user,
        page: pagination[:page],
        per_page: pagination[:per_page],
      )
    end

    validate_listing!(result)
    deliver_error! 404 unless result

    deliver :agent_variables_hash, { variables: result.variables, total_count: result.total_count }
  end

  get "/repositories/:repository_id/agents/organization-variables", operation_id: "agents/list-repo-organization-variables" do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :read_agent_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent variables are not available for public repositories",
      allow_integrations: true, allow_user_via_granular_actor: true

    deliver_error! 422 unless repo.organization_id

    @paginator = build_paginator(default_per_page: GitHub::KredzClient::Varz::DEFAULT_VARIABLES_PER_PAGE, max_per_page: GitHub::KredzClient::Varz::MAX_VARIABLES_PER_PAGE)

    result = rescue_from_variables_errors do
      Variables.list_repository_org_variables(
        repo,
        actor: current_user,
        app: self.class.agent_secrets_app,
        page: pagination[:page],
        per_page: pagination[:per_page],
      )
    end

    validate_listing!(result)
    deliver_error! 404 unless result

    deliver :agent_variables_hash, { variables: result.organization_variables, total_count: result.total_count }
  end

  get "/repositories/:repository_id/agents/variables/:name", operation_id: "agents/get-repo-variable" do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :read_agent_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent variables are not available for public repositories",
      allow_integrations: true,
      enforce_oauth_app_policy: true, allow_user_via_granular_actor: true

    result = rescue_from_variables_errors do
      Variables.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: repo,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :agent_variable_hash, result.variable
  end

  post "/repositories/:repository_id/agents/variables", operation_id: "agents/create-repo-variable", read_from_replicas: true do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :write_agent_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent variables are not available for public repositories",
      allow_integrations: true,
      enforce_oauth_app_policy: true, allow_user_via_granular_actor: true

    data = receive_with_openapi
    name = data["name"]
    value = data["value"]

    validation = Varz.validate_new_variable(name, value)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error
    end

    encoded_value = Base64.strict_encode64(value)

    result = rescue_from_variables_errors do
      Variables.store(
        name: name,
        app: self.class.agent_secrets_app,
        owner: repo,
        actor: current_user,
        value: encoded_value,
      )
    end

    validate_result!(result)
    validate_storage!(result)

    deliver_empty(status: 201)
  end

  patch "/repositories/:repository_id/agents/variables/:name", operation_id: "agents/update-repo-variable", read_from_replicas: true do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :write_agent_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent variables are not available for public repositories",
      allow_integrations: true,
      enforce_oauth_app_policy: true, allow_user_via_granular_actor: true

    data = receive_with_openapi
    updated_name = data["name"]
    value = data["value"]

    validation = Varz.validate_update_request(updated_name, value, current_user)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error
    end

    encoded_value = Base64.strict_encode64(value || "")

    result = rescue_from_variables_errors do
      Variables.update(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: repo,
        actor: current_user,
        value: encoded_value,
        updated_name: updated_name || "",
      )
    end

    validate_result!(result)
    validate_update!(result)

    deliver_empty(status: 204)
  end

  delete "/repositories/:repository_id/agents/variables/:name", operation_id: "agents/delete-repo-variable", read_from_replicas: true do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :write_agent_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent variables are not available for public repositories",
      allow_integrations: true,
      enforce_oauth_app_policy: true, allow_user_via_granular_actor: true

    receive_with_openapi

    result = rescue_from_variables_errors do
      Variables.delete(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: repo,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: (result.success ? 204 : 404)
  end

  private

  def agents_enabled?(repo)
    Secrets::AppsHelper.agents_enabled?(repo: repo, owner: repo.owner)
  end
end
