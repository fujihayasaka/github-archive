# typed: true
# frozen_string_literal: true

class Api::CopilotCodingAgent < Api::App
  include FeatureFlagHelper

  ALL = "all"
  SELECTED = "selected"
  NONE = "none"

  # Get the coding agent permissions for an organization
  get "/organizations/:organization_id/copilot/coding-agent/permissions",
    operation_id: "copilot/get-copilot-coding-agent-permissions-organization" do
    org = find_org!
    ensure_endpoint_enabled!(org)

    control_access :copilot_coding_agent_org_settings_reader,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    enabled_repositories = access_to_string(org.copilot_swe_agent_access)

    selected_repositories_url = if enabled_repositories == SELECTED
      url("/organizations/#{org.id}/copilot/coding-agent/permissions/repositories")
    end

    data = {
      enabled_repositories: enabled_repositories,
      selected_repositories_url: selected_repositories_url,
    }.compact

    deliver_raw(data, status: 200)
  end

  # Set the coding agent permissions for an organization
  put "/organizations/:organization_id/copilot/coding-agent/permissions", read_from_replicas: true,
    operation_id: "copilot/set-copilot-coding-agent-permissions-organization" do
    org = find_org!
    ensure_endpoint_enabled!(org)

    control_access :copilot_coding_agent_org_settings_writer,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi(expected_type: Hash)
    enabled_repositories = data["enabled_repositories"]

    access_value = case enabled_repositories
    when ALL
      Configurable::CopilotSweAgentAccess::State::ALL_REPOS.serialize
    when SELECTED
      Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS.serialize
    when NONE
      Configurable::CopilotSweAgentAccess::State::DISABLED.serialize
    end

    with_write(clusters: [ApplicationRecord::Configurations]) do
      org.update_copilot_swe_agent_access(access_value, false, actor: current_user)
    end

    deliver_empty status: 204
  end

  # List selected repositories enabled for coding agent in an organization
  get "/organizations/:organization_id/copilot/coding-agent/permissions/repositories",
    operation_id: "copilot/list-copilot-coding-agent-selected-repositories-for-organization" do
    org = find_org!
    ensure_endpoint_enabled!(org)

    control_access :copilot_coding_agent_org_settings_reader,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    check_coding_agent_selected!(org)

    enabled_repo_ids = CopilotSweAgent::RepoEnablement.for_repos_owned_by(org).pluck(:repository_id)
    enabled_repos = ::Repositories::Public.active_owned_by(org.id).where(id: enabled_repo_ids)
    total_count = enabled_repos.count

    paginated_repos = paginate_rel(enabled_repos)

    deliver :copilot_coding_agent_selected_repositories_hash, {
      total_count:,
      repositories: paginated_repos
    }
  end

  # Set selected repositories enabled for coding agent in an organization
  put "/organizations/:organization_id/copilot/coding-agent/permissions/repositories", read_from_replicas: true,
    operation_id: "copilot/set-copilot-coding-agent-selected-repositories-for-organization" do
    org = find_org!
    ensure_endpoint_enabled!(org)

    control_access :copilot_coding_agent_org_settings_writer,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    check_coding_agent_selected!(org)

    data = receive_with_openapi(expected_type: Hash)
    selected_repo_ids = data["selected_repository_ids"]

    valid_repo_count = org.repositories.where(id: selected_repo_ids).count
    if valid_repo_count != selected_repo_ids.count
      deliver_error!(422, message: "Some repositories in the given list do not belong to this organization.")
    end

    with_write(clusters: [ApplicationRecord::Copilot]) do
      CopilotSweAgent::RepoEnablement.enable_for_repositories!(
        repository_ids: selected_repo_ids,
        owner: org,
        enabled_by: current_user
      )
    end

    deliver_empty status: 204
  end

  # Enable a selected repository for coding agent in an organization
  put "/organizations/:organization_id/copilot/coding-agent/permissions/repositories/:repository_id", read_from_replicas: true,
    operation_id: "copilot/enable-copilot-coding-agent-for-repository-in-organization" do
    org = find_org!
    ensure_endpoint_enabled!(org)

    control_access :copilot_coding_agent_org_settings_writer,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    check_coding_agent_selected!(org)
    repository = find_and_check_repo!(org)

    unless CopilotSweAgent::RepoEnablement.enabled_for_repository?(repository)
      with_write(clusters: [ApplicationRecord::Copilot]) do
        CopilotSweAgent::RepoEnablement.find_or_create_by!(
          repository_id: repository.id,
          owner_id: org.id
        ) do |enablement|
          enablement.enabled_by_id = current_user.id
        end
      end
    end

    deliver_empty status: 204
  end

  # Disable a selected repository for coding agent in an organization
  delete "/organizations/:organization_id/copilot/coding-agent/permissions/repositories/:repository_id", read_from_replicas: true,
    operation_id: "copilot/disable-copilot-coding-agent-for-repository-in-organization" do
    org = find_org!
    ensure_endpoint_enabled!(org)

    control_access :copilot_coding_agent_org_settings_writer,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    check_coding_agent_selected!(org)
    repository = find_and_check_repo!(org)

    enablement = CopilotSweAgent::RepoEnablement.find_by(
      repository_id: repository.id,
      owner_id: org.id
    )

    if enablement
      with_write(clusters: [ApplicationRecord::Copilot]) do
        enablement.destroy_by(actor: current_user)
      end
    end

    deliver_empty status: 204
  end

  # Get the Copilot cloud agent configuration for a repository
  get "/repositories/:repository_id/copilot/cloud-agent/configuration",
    operation_id: "copilot/get-copilot-cloud-agent-configuration" do
    repo = find_repo!
    ensure_config_endpoint_enabled!(repo)

    control_access :copilot_cloud_agent_repo_settings_reader,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    config = Copilot::SweAgentConfiguration.find_by(resource: repo)

    mcp_configuration = config&.mcp_configuration
    parsed_mcp =
      if mcp_configuration.present?
        begin
          JSON.parse(mcp_configuration)
        rescue JSON::ParserError => e
          GitHub.logger.error("Failed to parse Copilot SWE agent MCP configuration", error: e, repository_id: repo.id)
          nil
        end
      end

    enabled_tools = {
      codeql: config&.use_codeql != false,
      copilot_code_review: config&.use_ccr != false,
      secret_scanning: config&.use_secret_scanning != false,
      dependency_vulnerability_checks: config&.use_dependency_vuln_checks != false,
    }

    require_actions_workflow_approval = config&.require_actions_workflow_approval_for_copilot_prs != false

    firewall = get_firewall_configuration(repo)

    data = {
      mcp_configuration: parsed_mcp,
      enabled_tools:,
      require_actions_workflow_approval:,
      is_firewall_enabled: firewall[:enabled],
      is_firewall_recommended_allowlist_enabled: firewall[:use_default_rules],
      custom_allowlist: firewall[:rules],
    }

    deliver_raw(data, status: 200)
  end

  private

  def ensure_repo_endpoint_enabled!(repo)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless GitHub.copilot_enabled?
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless repo.owner.copilot_swe_agent_enabled_for?(repo)
  end

  def ensure_config_endpoint_enabled!(repo)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless GitHub.copilot_enabled?
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless repo.owner.feature_flag_enabled?(:copilot_coding_agent_repo_configuration_api, default: false)
  end

  def get_firewall_configuration(repo)
    materialized = CopilotSweAgent::FirewallMaterializer.materialize(repo, current_user)
    {
      enabled: materialized[:enabled],
      use_default_rules: materialized[:use_default_rules],
      rules: materialized[:rules],
    }
  end

  def ensure_endpoint_enabled!(org)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless GitHub.copilot_enabled?
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless org.feature_flag_enabled?(:copilot_coding_agent_org_settings_api, default: false)
  end

  sig { params(access: Configurable::CopilotSweAgentAccess::State).returns(String) }
  def access_to_string(access)
    case access
    when Configurable::CopilotSweAgentAccess::State::ALL_REPOS
      ALL
    when Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
      SELECTED
    when Configurable::CopilotSweAgentAccess::State::DISABLED
      NONE
    else T.absurd(access)
    end
  end

  def check_coding_agent_selected!(org)
    access = T.cast(org.copilot_swe_agent_access, Configurable::CopilotSweAgentAccess::State)
    case access
    when Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
      # OK
    when Configurable::CopilotSweAgentAccess::State::DISABLED
      deliver_error!(409, message: "Copilot cloud agent is disabled for all repositories.")
    when Configurable::CopilotSweAgentAccess::State::ALL_REPOS
      deliver_error!(409, message: "Copilot cloud agent is enabled for all repositories.")
    else T.absurd(access)
    end
  end

  def find_and_check_repo!(org)
    repo = if FeatureFlag.vexi.enabled?(:repos_by_id_api, default: false)
      ::Repositories.domain.by_id(params[:repository_id].to_i)
    else
      Repository.find_by(id: params[:repository_id].to_i)
    end

    deliver_error!(404) unless repo
    deliver_error!(422, message: "Repository does not belong to this organization.") unless repo.owner_id == org.id
    repo
  end
end
