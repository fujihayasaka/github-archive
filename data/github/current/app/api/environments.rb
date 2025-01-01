# typed: true
# frozen_string_literal: true

class Api::Environments < Api::App
  include ReceiveSchemaWithOpenApi

  # Get list of environments
  get "/repositories/:repository_id/environments", operation_id: "repos/get-all-environments" do
    repo = find_repo!
    deliver_error! 404 unless repo.can_use_environments_api?

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    environments = paginate_rel(repo.environments)

    deliver :environments_hash, { environments: environments, total_count: environments.total_entries }
  end

  # Get single environment
  get "/repositories/:repository_id/environments/:environment", operation_id: "repos/get-environment" do
    repo = find_repo!
    deliver_error! 404 unless repo.can_use_environments_api?

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    environment = repo.environments.includes({ gates: :gate_approvers }).find_by(name: params[:environment])
    deliver_error! 404 unless environment.present?

    deliver :environment_hash_with_built_in_gates, environment
  end

  # Create or update an environment
  put "/repositories/:repository_id/environments/:environment", operation_id: "repos/create-or-update-environment" do
    repo = find_repo!
    deliver_error! 404 unless repo.can_use_environments_api?

    control_access :write_admin_actions_repo,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi
    begin
      environment = Environment.create_or_update_environment(repo, data, params[:environment])
    rescue Environment::EnvironmentError => error
      deliver_error!(422, message: error.to_s)
    end
    deliver :environment_hash_with_built_in_gates, environment
  end

  delete "/repositories/:repository_id/environments/:environment", operation_id: "repos/delete-an-environment" do
    repo = find_repo!
    deliver_error! 404 unless repo.can_use_environments_api?

    control_access :write_admin_actions_repo,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_schema("environment", "delete-environment")

    environment = repo.environments.includes(:gates).find_by(name: params[:environment])
    deliver_error! 404 if environment.nil?

    environment.destroy!
    deliver_empty(status: 204)
  end
end
