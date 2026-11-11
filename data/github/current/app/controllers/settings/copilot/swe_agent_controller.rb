# typed: true
# frozen_string_literal: true

class Settings::Copilot::SweAgentController < ApplicationController
  include Settings::ControllerMethods
  include ApplicationController::VerifiedFetchDependency
  include JsonDependency

  allow_verified_fetch only: [:update_repos, :toggle_third_party_agents_enablement]

  before_action :login_required
  before_action :redirect_on_no_emu_seat, only: [:index, :update_repos, :toggle_third_party_agents_enablement]
  before_action :parse_json_params, only: [:update_repos, :toggle_third_party_agents_enablement]

  stylesheet_bundle :suggestions, :copilot
  javascript_bundle :settings
  javascript_bundle :"copilot-swe-agent-repos-picker"
  javascript_bundle :"copilot-swe-agent-3p-enablement"
  javascript_bundle :"copilot-swe-agent-third-party-agent-picker"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index, :update_repos]

  def index
    return head :not_found if GitHub.multi_tenant_enterprise? && !FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, current_user, default: false)
    selected_repos = case copilot_user.copilot_swe_agent_access
    when Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
      CopilotSweAgent::RepoEnablement.enabled_repositories_for_owner(copilot_user.user_object).map { |repo| format_selected_repo(repo) }
    else
      []
    end

    render "settings/copilot/swe_agent", locals: {
      mode: copilot_user.copilot_swe_agent_access.serialize,
      selection: selected_repos,
      copilot_user: copilot_user,
      project_display_name: Copilot::COPILOT_SWE_AGENT,
      mode_changed_callback_path: copilot_swe_agent_update_repos_path,
      selections_changed_callback_path: copilot_swe_agent_update_repos_path,
      access_warning_banner_content: access_warning_banner_content,
      toggle_third_party_enablement_callback_path: copilot_swe_agent_toggle_third_party_enablement_path,
      per_app_ui: per_app_agents_enabled?(current_user),
      allow_third_party_agents: agentshq_enabled?(current_user), # only needed for non per-app-ui
      third_party_agents_enabled: current_user.swe_agent_third_party_access_enabled?, # only needed for non per-app-ui
      agents: per_app_agents_enabled?(current_user) ? populate_agents_props : [], # only relevant for per-app-ui
    }
  end

  def update_repos # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found unless GitHub.copilot_enabled?

    copilot_user.update_copilot_swe_agent_access(params[:mode], false, actor: copilot_user.user_object) if params[:mode].present?
    if copilot_user.copilot_swe_agent_access == Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
      CopilotSweAgent::RepoEnablement.enable_for_repositories!(repository_ids: params[:selected_repos], owner: copilot_user.user_object, enabled_by: copilot_user.user_object)
    end
    # Unsure if we need anything in the response payload
    head :ok
  end

  sig { void }
  def toggle_third_party_agents_enablement # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found unless agentshq_enabled?(current_user)
    return head :not_found unless GitHub.copilot_enabled?

    if per_app_agents_enabled?(current_user)
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
        if !agent.can_be_enabled_for?(current_user)
          render json: { success: false, message: "Agent #{agent_name} cannot be enabled for this user." }, status: 422
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
    else
      if current_user.swe_agent_third_party_access_enabled?
        current_user.disable_swe_agent_third_party_access(actor: current_user)

        # uninstall 3p apps
        agentic_apps.each do |app|
          installation = IntegrationInstallation.find_by(integration: app.integration, target: current_user)
          next unless installation

          UninstallIntegrationInstallationJob.perform_later(current_user.id, installation.id)
        end
      else
        current_user.enable_swe_agent_third_party_access(actor: current_user)

        # install 3p apps
        agentic_apps.each do |app|
          AutomaticAppInstallation.trigger(
            type: :third_party_agents_enabled,
            originator: app.integration,
            actor: current_user
          )
        end
      end
      head :ok
    end
  end

  private

  def format_selected_repo(repo)
    {
      id: repo.id,
      name: repo.name,
      ownerLogin: repo.owner.display_login,
      visibility: repo.visibility,
    }
  end

  memoize def copilot_user
    T.must_because(current_copilot_user) { "#login_required ensures non-nil" }
  end

  sig { void }
  def redirect_on_no_emu_seat
    if copilot_user.is_enterprise_managed?
      redirect_to "/settings/profile" unless copilot_user.has_enterprise_seat?
    end
  end

  sig { returns(T.nilable(String)) }
  def access_warning_banner_content
    public_user = Copilot::Public::User.new(current_user)

    if !public_user.has_copilot_access? || !public_user.has_required_sku_for_copilot_coding_agent?
      return "You can enable Copilot coding agent for other users, but you won't be able to assign tasks to Copilot because you don't have a Copilot Pro, Copilot Pro+, Copilot Business or Copilot Enterprise license."
    elsif !public_user.swe_agent_enabled?
      return "You can enable Copilot coding agent for other users, but you won't be able to assign tasks to Copilot because the Copilot coding agent policy has been disabled by an administrator."
    end

    nil
  end

  sig { returns(T::Array[AgenticApp]) }
  def agentic_apps
    AgenticApp.all_agents.reject(&:global?).reject { |app| app.integration.nil? }
  end

  sig { params(user: User).returns(T::Boolean) }
  def agentshq_enabled?(user)
    FeatureFlag.vexi.enabled?(:agentshq_policy, user, default: false)
  end

  sig { params(user: User).returns(T::Boolean) }
  def per_app_agents_enabled?(user)
    FeatureFlag.vexi.enabled?(:agentshq_per_app_agents, user, default: false)
  end

  sig { returns(T::Array[Hash]) }
  def populate_agents_props
    # filter out agents that are not enabled via feature flag
    agents = agentic_apps.select do |app|
      app.can_be_enabled_for?(current_user)
    end

    return [] if agents.empty?
    agents_props = agents.map do |agent|
      {
        name: agent.slug,
        displayName: agent.display_name,
        enabled: current_user.swe_agent_third_party_access_enabled?(agent: agent),
      }
    end
    agents_props
  end

  sig { params(agent: AgenticApp).returns(T.untyped) }
  def install_agent(agent)
    AutomaticAppInstallation.trigger(
      type: :third_party_agents_enabled,
      originator: agent.integration,
      actor: current_user,
      async: true
    )
  end

  sig { params(agent: AgenticApp).returns(T.untyped) }
  def uninstall_agent(agent)
    installation = IntegrationInstallation.find_by(integration: agent.integration, target: current_user)
    return unless installation

    UninstallIntegrationInstallationJob.perform_later(current_user.id, installation.id)
  end
end
