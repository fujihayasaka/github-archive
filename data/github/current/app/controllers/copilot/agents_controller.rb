# typed: true
# frozen_string_literal: true

# Standalone controller for /copilot/agents that renders with the standard
# GitHub layout (GlobalNav) instead of the copilot-immersive shell.
# Gated behind the copilot_mission_control_agents_page_redesign feature flag.
# When the flag is off, delegates to the existing immersive controller.
class Copilot::AgentsController < ApplicationController
  include GitHub::Memoizer
  include MissionControlExperimentEvents
  helper CopilotChatHelper

  global_navigation_title "Agents", only: [:show]

  before_action :login_required
  before_action :delegate_to_immersive_unless_flag_enabled

  # rubocop:disable GitHub/SpecifyResourceForConditionalAccess, GitHub/UseRestfulActions
  def resource_for_conditional_access
    :no_resource_for_conditional_access
  end
  # rubocop:enable GitHub/SpecifyResourceForConditionalAccess, GitHub/UseRestfulActions

  # rubocop:disable GitHub/SpecifyTargetForConditionalAccess, GitHub/UseRestfulActions
  def target_for_conditional_access
    :no_target_for_conditional_access
  end
  # rubocop:enable GitHub/SpecifyTargetForConditionalAccess, GitHub/UseRestfulActions

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show]
  )

  TURBO_CONFIG = {
    id: "repo-content-turbo-frame",
    target: "_top",
    action: "advance",
  }.freeze

  PAGE_DATA = {
    hide_footer: true,
  }.freeze

  def show
    user = T.must(current_user)

    emit_experiment_exposure(
      surface_type: :AGENT_SURFACE_TYPE_IMMERSIVE,
      entry_point: "copilot_agents_standalone",
    )

    token = if agent_tasks_enabled?
      CopilotSessions::CopilotApiToken.get_encrypted(
        user: user,
        entry_point: :copilot_agents_controller_show,
        user_session: user_session
      )
    end

    payload = {
      agentsEnabled: agent_tasks_enabled?,
      hasCEorCBAccess: has_ce_or_cb_access?,
      memberRequestEntities: helpers.get_member_requests_payload(user),
      currentUser: CopilotSessions::Payloads::PublicUser.new(user).call,
      sessionsPollingInterval: CopilotSessions::Public.copilot_sessions_polling_interval_seconds.value * 1000.0,
      logsPollingInterval: CopilotSessions::Public.copilot_logs_polling_interval_seconds.value * 1000.0,
      useTokenBasedBilling: use_token_based_billing?,
      showCopilotCodingAgentPremiumRequestsBanner: CopilotSessions::Public.show_copilot_coding_agent_premium_requests_banner(user),
      agentQuotaSnapshot: helpers.agent_quota_snapshot_for_user(user),
    }

    if token
      payload[:initialAuthToken] = {
        token: token.value,
        expiration: token.expiration&.iso8601,
        ssoOrgIDs: saml_for_user.protected_organization_ids.map(&:to_s),
      }
    end

    respond_to do |format|
      format.html do
        render_react_html(
          title: "Agents · GitHub Copilot",
          payload: { copilotAgentsRoute: payload },
          app_name: "copilot-agents",
          page_data: PAGE_DATA,
          turbo: TURBO_CONFIG,
        )
      end
      format.json do
        render_react_json(title: "Agents · GitHub Copilot", payload: { copilotAgentsRoute: payload })
      end
    end
  end

  private

  def delegate_to_immersive_unless_flag_enabled
    unless FeatureFlag.vexi.enabled?(:copilot_mission_control_agents_page_redesign, T.must(current_user), default: false) &&
           AssetBundles.new.bundle_exists?("copilot-agents.js")
      # Dispatch to the existing immersive controller when the flag is off
      # or when the standalone bundle is not yet available.
      response_status, response_headers, response_body = Copilot::Immersive::AgentTasksController.action(:show).call(request.env)
      self.status = response_status
      response_headers.each { |key, value| response.headers[key] = value }
      self.response_body = response_body
    end
  end

  memoize def copilot_user
    Copilot::Public::User.for(T.must(current_user))
  end

  memoize def agent_tasks_enabled?
    copilot_user.swe_agent_enabled?
  end

  memoize def use_token_based_billing?
    copilot_user.use_token_based_billing?
  end

  memoize def has_ce_or_cb_access?
    copilot_user.has_copilot_access? && copilot_user.show_copilot_functionality?
  end
end
