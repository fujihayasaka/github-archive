# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::SweAgentController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include JsonDependency
  include AgenticAppConflictCheck

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::CopilotSettings::SweAgentController#update_firewall_configuration",
  ].freeze

  allow_verified_fetch only: [:update_repos, :toggle_third_party_agents_enablement, :update_firewall_configuration, :update_runner_settings, :update_automations_disabled, :update_trigger_actor_policy]

  before_action :login_required
  before_action :dotcom_required
  before_action :org_admins_only
  before_action :parse_json_params, only: [:update_repos, :toggle_third_party_agents_enablement, :update_firewall_configuration, :update_runner_settings, :update_automations_disabled, :update_trigger_actor_policy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index, :firewall_allowlist_edit, :update_firewall_configuration]

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-for-business"
  end

  sig { void }
  def index
    return head :not_found if GitHub.multi_tenant_enterprise? && !FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, current_organization, default: false)
    if FeatureFlag.vexi.enabled?(:cfb_package_data_router, current_user, default: false)
      respond_with_react(
        payload: IndexPayload.new(payload: index_payload),
        title: Copilot::COPILOT_SWE_AGENT,
        layout: "layouts/settings/copilot_org_react",
        page_data: { selected_link: :organization_copilot_settings_swe_agent }
      )
    else
      render_react_app(
        payload: IndexPayload.new(payload: index_payload).payload,
        title: Copilot::COPILOT_SWE_AGENT,
        layout: "layouts/settings/copilot_org_react",
        disable_ssr: true,
        page_data: { selected_link: :organization_copilot_settings_swe_agent }
      )
    end
  end

  sig { void }
  def update_repos # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless repo_access_enabled?
    return head :not_found unless request.xhr?
    return head :not_found unless GitHub.copilot_enabled?

    current_organization.update_copilot_swe_agent_access(params[:mode], false, actor: current_user) if params[:mode].present?
    if current_organization.copilot_swe_agent_access == Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
      CopilotSweAgent::RepoEnablement.enable_for_repositories!(repository_ids: params[:selected_repos], owner: current_organization, enabled_by: current_user)
    end
    # Unsure if we need anything in the response payload
    head :ok
  end

  sig { void }
  def toggle_third_party_agents_enablement # rubocop:disable GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found unless agentshq_enabled?(current_organization)

    agent_name = params[:agent]
    enabled = params[:enabled].to_s.downcase

    agent = agentic_apps.find { |app| app.slug == agent_name }
    unless agent
      error_message = "Invalid agent #{agent_name}"
      render json: { success: false, message: error_message }, status: 422
      return
    end

    case enabled
    when "true"
      # check if the agent is installable
      if !agent.can_be_enabled_for?(current_organization)
        render json: { success: false, message: "Agent #{agent_name} cannot be enabled for this organization." }, status: 422
        return
      end
      install_agent(agent)
    when "false"
      # we don't need to check for enablement
      uninstall_agent(agent)
    else
      render json: { success: false, message: "Invalid enabled value #{enabled}" }, status: 422
      return
    end

    render json: { success: true }, status: 200
  end

  sig { void }
  def firewall_allowlist_edit # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless firewall_ui_enabled?

    firewall_payload = {
      firewallConfiguration: firewall_service.config,
      endpoint: settings_org_copilot_swe_agent_path,
    }

    if FeatureFlag.vexi.enabled?(:cfb_package_data_router, current_user, default: false)
      respond_with_react(
        payload: FirewallAllowlistPayload.new(payload: firewall_payload),
        title: Copilot::COPILOT_SWE_AGENT,
        layout: "layouts/settings/copilot_org_react",
        page_data: { selected_link: :organization_copilot_settings_swe_agent }
      )
    else
      render_react_app(
        payload: FirewallAllowlistPayload.new(payload: firewall_payload).payload,
        title: Copilot::COPILOT_SWE_AGENT,
        layout: "layouts/settings/copilot_org_react",
        disable_ssr: true,
        page_data: { selected_link: :organization_copilot_settings_swe_agent }
      )
    end
  end

  sig { void }
  def update_firewall_configuration # rubocop:disable GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return render json: { error: "Firewall UI is not enabled" }, status: :unprocessable_entity unless firewall_ui_enabled?

    # Each value can be true, false, or nil ("No policy" / defer to repo).
    # params.key? checks the param was sent at all (vs omitted entirely).
    enabled = cast_nullable_boolean_param(:enabled)
    use_default_rules = cast_nullable_boolean_param(:useDefaultRules)
    allow_custom_rules = cast_nullable_boolean_param(:allowCustomRules)

    unless params.key?(:enabled) && params.key?(:useDefaultRules) && params.key?(:allowCustomRules)
      return render json: { error: "The 'enabled', 'useDefaultRules', and 'allowCustomRules' parameters are required (may be null for 'No policy')" }, status: :unprocessable_entity
    end

    result = firewall_service.update(
      enabled: enabled,
      use_default_rules: use_default_rules,
      allow_custom_rules: allow_custom_rules,
      actor: current_user,
      rules: params[:rules],
    )

    render json: result
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  rescue StandardError => e
    Failbot.report(e)
    render json: { error: "An unexpected error occurred" }, status: :internal_server_error
  end

  sig { void }
  def update_runner_settings # rubocop:disable GitHub/UseRestfulActions
    return head :not_found if runner_type_standalone_enabled?
    return head :not_found unless request.xhr?
    return head :not_found unless FeatureFlag.vexi.enabled?(:copilot_swe_agent_runner_control_settings, current_organization, default: false)

    current_organization.update_copilot_swe_agent_runner(
      runner_type: params[:runner_type],
      runner_labels: params[:runner_labels] || "",
      runner_group_name: params[:runner_group_name] || "",
      allow_repo_custom_runner: params[:allow_repo_custom_runner].nil? ? nil : ActiveModel::Type::Boolean.new.cast(params[:allow_repo_custom_runner]),
      actor: current_user,
    )

    head :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Failbot.report(e)
    head :unprocessable_entity
  end

  # Toggle the organization-level kill switch that disables triggered
  # (automated) Copilot coding agent sessions across the org. Accepts a
  # nullable boolean param `automations_disabled`:
  # - true  : disable triggered automations org-wide
  # - false : explicitly allow (clears any inherited disable)
  # - null  : no policy, defer to repo-level setting
  # Does not affect user-initiated (U2S) flows.
  sig { void }
  def update_automations_disabled # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless automations_ui_enabled?

    unless params.key?(:automations_disabled)
      return render json: { error: "The 'automations_disabled' parameter is required (may be null for 'No policy')" }, status: :unprocessable_entity
    end

    raw = params[:automations_disabled]
    disabled = raw.nil? ? nil : ActiveModel::Type::Boolean.new.cast(raw)
    if !raw.nil? && disabled.nil?
      return render json: { error: "The 'automations_disabled' parameter must be a boolean or null" }, status: :unprocessable_entity
    end

    current_organization.update_copilot_swe_agent_automations_disabled(disabled: disabled, actor: current_user)

    render json: {
      message: "Setting saved successfully",
      automationsDisabled: current_organization.copilot_swe_agent_automations_disabled_policy,
    }
  end

  sig { void }
  def update_trigger_actor_policy # rubocop:disable GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found unless automations_ui_enabled?

    # Strict-boolean check: avoid `cast_nullable_boolean_param`, whose underlying
    # `ActiveModel::Type::Boolean.cast` only treats explicit-falsy strings ("false"/
    # "0"/"f"/"off") as `false` and silently coerces everything else (including
    # malformed strings like "no") to `true`. That asymmetry would let a request
    # with `allow_read_access_triggers: "no"` flip the policy to enabled.
    value = params[:allow_read_access_triggers]
    return head :unprocessable_entity unless value.is_a?(TrueClass) || value.is_a?(FalseClass)

    current_organization.update_copilot_swe_agent_allow_read_access_triggers(value: value, actor: current_user)

    head :ok
  rescue StandardError => e
    Failbot.report(e)
    head :unprocessable_entity
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  def index_payload
    selected_repos = case current_organization.copilot_swe_agent_access
    when Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
      CopilotSweAgent::RepoEnablement.enabled_repositories_for_owner(current_organization).map { |repo| format_selected_repo(repo) }
    else
      []
    end

    business = current_organization.business
    payload = {
      project_display_name: Copilot::COPILOT_SWE_AGENT,
      selection: selected_repos,
      org_login: current_organization.display_login,
      enterprise_name: business&.name,
      enterprise_slug: business&.slug,
      mode: current_organization.copilot_swe_agent_access.serialize,
      mode_changed_callback_path: settings_org_copilot_swe_agent_update_repos_path,
      selections_changed_callback_path: settings_org_copilot_swe_agent_update_repos_path,
      access_warning_banner_content: access_warning_banner_content,
      repo_access_enabled: repo_access_enabled?,
      third_party_agent_enablement_callback_path: settings_org_copilot_swe_agent_toggle_third_party_agents_enablement_path,
      agents: populate_agents_props,
    }

    if FeatureFlag.vexi.enabled?(:copilot_swe_agent_runner_control_settings, current_organization, default: false)
      if runner_type_standalone_enabled?
        payload[:runnerTypeOnStandalonePage] = true
        payload[:runnerTypeStandalonePath] = settings_org_copilot_runner_type_path
      else
        payload[:runner_type] = current_organization.copilot_swe_agent_runner_type
        payload[:runner_labels] = current_organization.copilot_swe_agent_runner_labels
        payload[:runner_group_name] = current_organization.copilot_swe_agent_runner_group_name
        payload[:allow_repo_custom_runner] = current_organization.copilot_swe_agent_allow_repo_custom_runner
        payload[:runner_settings_changed_callback_path] = settings_org_copilot_swe_agent_update_runner_settings_path
      end
    end

    if firewall_ui_enabled?
      payload[:firewallConfiguration] = firewall_service.config
      payload[:firewallEndpoint] = settings_org_copilot_swe_agent_update_firewall_path
      payload[:firewallAllowlistPath] = settings_org_copilot_swe_agent_allowlist_path
    end

    payload[:automationsUiEnabled] = automations_ui_enabled?
    if automations_ui_enabled?
      payload[:automationsDisabled] = current_organization.copilot_swe_agent_automations_disabled_policy
      payload[:automationsDisabledEndpoint] = settings_org_copilot_swe_agent_update_automations_disabled_path
    end

    if automations_ui_enabled?
      payload[:allow_read_access_triggers] = current_organization.copilot_swe_agent_allow_read_access_triggers_policy
      payload[:trigger_actor_policy_changed_callback_path] = settings_org_copilot_swe_agent_update_trigger_actor_policy_path
    end

    payload
  end

  sig { params(repo: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
  def format_selected_repo(repo)
    {
      id: repo.id,
      name: repo.name,
      ownerLogin: repo.owner.display_login,
      visibility: repo.visibility,
    }
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end

  sig { returns(T::Boolean) }
  memoize def repo_access_enabled?
    business = current_organization.business
    business.nil? || business.swe_agent_repository_access_enabled?
  end

  sig { returns(T.nilable(String)) }
  def access_warning_banner_content
    return nil unless repo_access_enabled?
    public_user = Copilot::Public::User.for(current_user)

    if !public_user.has_copilot_access? || !public_user.has_required_sku_for_copilot_coding_agent?
      return "You can enable Copilot cloud agent for other users, but you won't be able to assign tasks to Copilot because you don't have a Copilot Pro, Copilot Pro+, Copilot Business or Copilot Enterprise license."
    elsif !public_user.swe_agent_enabled?
      return "You can enable Copilot cloud agent for other users, but you won't be able to assign tasks to Copilot because the Copilot cloud agent policy has been disabled by an administrator."
    end

    nil
  end

  sig { returns(T::Array[AgenticApp]) }
  def agentic_apps
    AgenticApp.partner_agents.reject { |app| app.integration.nil? }
  end

  sig { params(org: Organization).returns(T::Boolean) }
  def agentshq_enabled?(org)
    FeatureFlag.vexi.enabled?(:agentshq_policy, org, default: false)
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def populate_agents_props
    # filter out agents that are not enabled via feature flag
    agents = agentic_apps.select do |app|
      app.can_be_enabled_for?(current_organization)
    end

    return [] if agents.empty?
    agents_props = agents.map do |agent|
      {
        name: agent.slug,
        displayName: agent.display_name,
        docUrl: agent.doc_url,
        enabled: agent.installed_for_target?(current_organization),
        blockedByConflict: target_has_conflicting_app_installed?(agent, current_organization),
      }
    end
    agents_props
  end

  sig { params(agent: AgenticApp).returns(T.untyped) }
  def install_agent(agent)
    AutomaticAppInstallation.trigger(
      type: :third_party_agents_enabled,
      originator: agent.integration,
      actor: current_organization,
      async: true
    )
  end

  sig { params(agent: AgenticApp).returns(T.untyped) }
  def uninstall_agent(agent)
    installation = IntegrationInstallation.find_by(integration: agent.integration, target: current_organization)
    return unless installation

    UninstallIntegrationInstallationJob.perform_later(current_user.id, installation.id)
  end

  sig { returns(CopilotSweAgent::FirewallConfigurationService) }
  memoize def firewall_service
    CopilotSweAgent::FirewallConfigurationService.new(current_organization)
  end

  sig { returns(T::Boolean) }
  def firewall_ui_enabled?
    FeatureFlag.vexi.enabled?(:sweagentd_org_firewall, current_user, default: false)
  end

  sig { returns(T::Boolean) }
  def runner_type_standalone_enabled?
    FeatureFlag.vexi.enabled?(:ccr_runner_type_org_settings, current_organization, default: false) &&
      FeatureFlag.vexi.enabled?(:copilot_swe_agent_runner_control_settings, current_organization, default: false)
  end

  # Gate for the organization-level automations kill switch UI + endpoint.
  # Mirrors the repo-level gate in `Repos::CopilotSettings::SweAgentController`:
  # both ride the master triggers feature flag rollout — no separate UI flag
  # so we don't have to manage and clean up an extra rollout flag.
  sig { returns(T::Boolean) }
  def automations_ui_enabled?
    FeatureFlag.vexi.enabled?(:copilot_swe_agent_custom_agent_triggers, current_organization, default: false)
  end

  sig { params(key: Symbol).returns(T.nilable(T::Boolean)) }
  def cast_nullable_boolean_param(key)
    value = params[key]
    return nil if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end

  class IndexPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "copilotForBusinessSweAgentRoute"
    end

    sig { params(payload: T::Hash[String, T.untyped]).void }
    def initialize(payload:)
      @payload = payload
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      @payload
    end
  end

  class FirewallAllowlistPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "copilotForBusinessSweAgentFirewallRoute"
    end

    sig { params(payload: T::Hash[String, T.untyped]).void }
    def initialize(payload:)
      @payload = payload
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      @payload
    end
  end
end
