# typed: true
# frozen_string_literal: true

require "github/kredz_client"

class Api::ActionsVariables < Api::App
  include Api::App::ActionsVariablesHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  # For Local development, you need bin/server running and github/kredz running (varz service)

  # List repository variables
  get "/repositories/:repository_id/actions/variables", operation_id: "actions/list-repo-variables" do
    repo = find_repo!
    deliver_error! 404 unless can_use_variables_api?(repo.owner)

    control_access :read_actions_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_VARIABLES_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    @paginator = build_paginator(default_per_page: GitHub::KredzClient::Varz::DEFAULT_VARIABLES_PER_PAGE, max_per_page: GitHub::KredzClient::Varz::MAX_VARIABLES_PER_PAGE)

    result = rescue_from_variables_errors do
      Variables.list(
        app: GitHub.launch_github_app,
        owner: repo,
        actor: current_user,
        page: pagination[:page],
        per_page: pagination[:per_page],
      )
    end

    validate_listing!(result)
    deliver_error! 404 unless result

    deliver :actions_variables_hash, { variables: result.variables, total_count: result.total_count }
  end

  # List organization variables shared with a repository
  get "/repositories/:repository_id/actions/organization-variables", operation_id: "actions/list-repo-organization-variables" do
    repo = find_repo!
    deliver_error! 404 unless can_use_variables_api?(repo.owner)

    control_access :read_actions_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_VARIABLES_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 422 unless repo.organization_id

    @paginator = build_paginator(default_per_page: GitHub::KredzClient::Varz::DEFAULT_VARIABLES_PER_PAGE, max_per_page: GitHub::KredzClient::Varz::MAX_VARIABLES_PER_PAGE)

    result = rescue_from_variables_errors do
      Variables.list_repository_org_variables(
        repo,
        actor: current_user,
        app: GitHub.launch_github_app,
        page: pagination[:page],
        per_page: pagination[:per_page],
      )
    end

    validate_listing!(result)
    deliver_error! 404 unless result

    deliver :actions_variables_hash, { variables: result.organization_variables, total_count: result.total_count }
  end

  # Get a single variable
  get "/repositories/:repository_id/actions/variables/:name", operation_id: "actions/get-repo-variable" do
    repo = find_repo!
    deliver_error! 404 unless can_use_variables_api?(repo.owner)

    control_access :read_actions_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_VARIABLES_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_variables_errors do
      Variables.fetch(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: repo,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :actions_variable_hash, result.variable
  end

  # Create a variable for actions on repository for a write user.
  post "/repositories/:repository_id/actions/variables", operation_id: "actions/create-repo-variable" do
    repo = find_repo!
    deliver_error! 404 unless can_use_variables_api?(repo.owner)

    control_access :write_actions_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_VARIABLES_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

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
        app: GitHub.launch_github_app,
        owner: repo,
        actor: current_user,
        value: encoded_value,
      )
    end

    validate_result!(result)
    validate_storage!(result)

    deliver_empty(status: 201)
  end

  # Update a variable for actions on repository for a write user.
  patch "/repositories/:repository_id/actions/variables/:name", operation_id: "actions/update-repo-variable" do
    repo = find_repo!
    deliver_error! 404 unless can_use_variables_api?(repo.owner)

    control_access :write_actions_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_VARIABLES_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

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
        app: GitHub.launch_github_app,
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

  # Delete a variable
  delete "/repositories/:repository_id/actions/variables/:name", operation_id: "actions/delete-repo-variable" do
    repo = find_repo!
    deliver_error! 404 unless can_use_variables_api?(repo.owner)

    control_access :write_actions_variables_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_VARIABLES_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    result = rescue_from_variables_errors do
      Variables.delete(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: repo,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: (result.success ? 204 : 404)
  end

  private

  # Only let orgs with actions and variables FF enabled to access this API
  def can_use_variables_api?(owner)
    GitHub.actions_enabled?
  end
end
