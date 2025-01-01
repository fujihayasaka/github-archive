# typed: true
# frozen_string_literal: true

class Api::DeploymentProtectionRules < Api::App
  include ReceiveSchemaWithOpenApi

  # Get list of deployment protection rules for an environment
  get "/repositories/:repository_id/environments/:environment_name/deployment_protection_rules", operation_id: "repos/get-all-deployment-protection-rules" do
    repo = find_repo!

    deliver_error! 404 unless repo.can_use_environments_api?

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    log_strict_auth_failures(repo)

    environment = Environment.find_by(repository: repo, name: params[:environment_name])
    deliver_error! 404 unless environment

    custom_gates = environment.custom_gates.to_a
    total_count = custom_gates.count
    integrations = Integration.where(id: custom_gates.pluck(:integration_id))

    deliver :deployment_protection_rules_hash, { gates: custom_gates, environment: environment, total_count: total_count, integrations: integrations }, status: 200
  end

  # Get a list of deployment protection rule integrations that are available for an environment
  get "/repositories/:repository_id/environments/:environment_name/deployment_protection_rules/apps", operation_id: "repos/list-custom-deployment-rule-integrations" do
    repo = find_repo!

    deliver_error! 404 unless repo.can_use_environments_api?

    control_access :read_admin_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    owner = repo&.owner
    deliver_error! 404 if owner.nil?

    environment = Environment.find_by(repository: repo, name: params[:environment_name])
    deliver_error! 404 unless environment

    integrations = environment.available_disabled_custom_gate_apps

    paginated_integrations = paginate_rel(integrations)
    deliver :custom_deployment_rule_integrations_hash, { integrations: paginated_integrations, total_count: integrations.count }, status: 200
  end

  # Get a deployment protection rule
  get "/repositories/:repository_id/environments/:environment_name/deployment_protection_rules/:protection_rule_id", operation_id: "repos/get-custom-deployment-protection-rule" do
    repo = find_repo!

    deliver_error! 404 unless repo.can_use_environments_api?

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    log_strict_auth_failures(repo)

    environment = Environment.find_by(repository: repo, name: params[:environment_name])

    deliver_error! 404 unless environment

    gate = environment.custom_gates.find_by(id: params[:protection_rule_id])
    deliver_error! 404 unless gate

    # integration = Integration.find(gate&.integration_id)

    deliver :deployment_protection_rule_hash, { gate: gate, environment: environment, integration: gate.integration }, status: 200
  end

  # Enable a custom deployment protection rule for an environment
  post "/repositories/:repository_id/environments/:environment/deployment_protection_rules", operation_id: "repos/create-deployment-protection-rule" do
    repo = find_repo!

    deliver_error! 404 unless repo.can_use_environments_api?

    control_access :write_admin_actions_repo,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    owner = repo&.owner
    deliver_error! 404 if owner.nil?

    environment = Environment.find_by(repository: repo, name: params[:environment])
    deliver_error! 404 unless environment

    data = receive_with_openapi
    integration_id = data["integration_id"]
    custom_gates_integration_ids = environment.custom_gate_integrations.pluck(:id)

    if custom_gates_integration_ids.include?(integration_id)
      deliver_error!(422, {
        message: "Custom deployment protection rule for this app already exists on this environment",
        errors: [
          api_error(:DeploymentProtectionRule, :integration_id, :already_exists)
        ]
      })
    end

    installation = IntegrationInstallation.find_by(integration_id: integration_id, target: owner)

    unless installation
      deliver_error!(422, {
        message: "App not installed on organization",
        errors: [
          api_error(:DeploymentProtectionRule, :integration_id, :unprocessable)
        ]
      })
    end

    installed_on_repo = installation.repository_ids(repository_ids: [repo.id]).any?

    unless installed_on_repo
      deliver_error!(422, {
        message: "App not enabled for repository",
        errors: [
          api_error(:DeploymentProtectionRule, :integration_id, :unprocessable)
        ]
      })
    end

    custom_gates_integration_ids << integration_id

    begin
      result = environment.create_or_update_custom_protection_rules(custom_gates_integration_ids)
    rescue Environment::EnvironmentError => error
      deliver_error!(422, message: error.to_s)
    end

    gate = result.find { |gate| gate.integration_id == integration_id }

    deliver :deployment_protection_rule_hash, { gate: gate, environment: environment, integration: installation.integration }, full: true, status: 201
  end

  # Disable a custom deployment protection rule for an environment
  delete "/repositories/:repository_id/environments/:environment_name/deployment_protection_rules/:protection_rule_id", operation_id: "repos/disable-deployment-protection-rule" do
    repo = find_repo!

    deliver_error! 404 unless repo.can_use_environments_api?

    control_access :write_admin_actions_repo,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    environment = Environment.find_by(repository: repo, name: params[:environment_name])
    deliver_error! 404 unless environment

    gate = environment.custom_gates.find_by(id: params[:protection_rule_id])
    deliver_error! 404 unless gate

    begin
      gate.destroy! unless gate.nil?
    rescue ActiveRecord::RecordNotFound
      return deliver_error 404
    rescue ActiveRecord::ActiveRecordError
      return deliver_error 500, message: "Protection rule not disabled."
    end

    deliver_empty(status: 204)
  end

  # Log if requiring admin read permission would have resulted in an error
  # as part of https://github.com/github/actions-fusion/issues/1708
  def log_strict_auth_failures(repo)
    if FeatureFlag.vexi.enabled_or_raise?(:deployment_protection_rules_log_strict_auth, repo) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      # New proposed permission check: require read_admin_actions
      # same as other repo-level Actions settings
      has_read_admin = access_allowed?(:read_admin_actions,
        resource: repo,
        forbid: repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: repo.private?
      )

      GitHub.logger.info("Would have failed strict auth check for deployment protection rules",
        "code.namespace" => "Api::DeploymentProtectionRules",
        "code.function" => "log_strict_auth_failures",
        "gh.user.id" => current_user&.id,
        "gh.user.is_staff" => current_user&.employee?,
        "gh.repo.id" => repo&.id,
        "gh.repo.visibility" => repo&.visibility,
        "gh.owner.id" => repo&.owner&.id,
      ) unless has_read_admin
    end
  end
end
